# ---------------------------------------------------------------------------
# EKS cluster IAM role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.common_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_eks_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# EKS worker node IAM role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.common_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

locals {
  node_iam_policy = [
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy"
  ]
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Required by the cilium-operator (ENI IPAM mode) to manage ENIs and pod IPs.
resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# NOTE: AmazonEKS_CNI_Policy is attached even though the AWS VPC CNI is not
# installed. Cilium runs in ENI IPAM mode, so the cilium-operator calls the EC2
# API with the node role credentials to create, attach and assign IPs to ENIs.
# Without it the operator fails with "UnauthorizedOperation" on
# ec2:DescribeNetworkInterfaces and the cilium agent never becomes ready.

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller IAM role for service accounts (IRSA)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "eks" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "nlb_controller_assume_role" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(aws_iam_openid_connect_provider.eks[0].url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(aws_iam_openid_connect_provider.eks[0].url, "https://")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "nlb_controller" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  name               = "${local.common_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.nlb_controller_assume_role[0].json
}

locals {
  nlb_controller_version     = "3.6.2"
  nlb_controller_policy_file = "${path.module}/aws-load-balancer-controller-v${local.nlb_controller_version}-iam-policy.json"
}

# Downloads the official IAM policy of the AWS Load Balancer Controller when
# enable_nlb_iam_permissions = true. It runs again if the controller version changes.
# Docs: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
resource "terraform_data" "nlb_controller_policy_download" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  triggers_replace = [local.nlb_controller_version]

  provisioner "local-exec" {
    command = "curl -fsSL -o ${local.nlb_controller_policy_file} https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${local.nlb_controller_version}/docs/install/iam_policy.json"
  }
}

resource "aws_iam_policy" "nlb_controller" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  name   = "aws-nlb-iam-policy"
  policy = file(local.nlb_controller_policy_file)

  depends_on = [terraform_data.nlb_controller_policy_download]
}

resource "aws_iam_role_policy_attachment" "nlb_controller" {
  count = local.enable_nlb_iam_permissions ? 1 : 0

  role       = aws_iam_role.nlb_controller[0].name
  policy_arn = aws_iam_policy.nlb_controller[0].arn
}
