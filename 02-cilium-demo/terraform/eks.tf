# ---------------------------------------------------------------------------
# EKS control plane
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = local.common_name
  role_arn = aws_iam_role.cluster.arn
  version  = local.cluster_version

  # Do not install AWS self-managed add-ons (vpc-cni, kube-proxy, coredns).
  # Cilium will be installed later as the cluster CNI and kube-proxy
  # replacement, so we keep the control plane free of the default networking.
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      module.vpc.subnets_private_raw["cilium-private-eks-a"].id,
      module.vpc.subnets_private_raw["cilium-private-eks-b"].id,
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name = local.common_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_policy,
  ]
}

# ---------------------------------------------------------------------------
# Managed node group - single cheap SPOT node for the demo
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  count = local.is_eks_initialized ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.common_name}-ng"
  node_role_arn   = aws_iam_role.node.arn

  subnet_ids = [
    module.vpc.subnets_private_raw["cilium-private-eks-a"].id,
    module.vpc.subnets_private_raw["cilium-private-eks-b"].id,
  ]

  # Cheapest sensible footprint for a learning cluster.
  capacity_type  = "SPOT"
  instance_types = ["t3.small"]
  disk_size      = 20

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${local.common_name}-ng"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
    module.vpc,
  ]
}

resource "aws_eks_addon" "this" {
  for_each = local.is_eks_initialized ? local.eks_addons : toset([])

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.value

  depends_on = [
    aws_eks_node_group.this,
  ]
}