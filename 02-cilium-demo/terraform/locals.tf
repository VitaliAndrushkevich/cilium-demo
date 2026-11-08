locals {
  common_name                = "cilium-demo-02"
  cluster_version            = "1.37"
  is_eks_initialized         = true
  enable_nlb_iam_permissions = false

  # EKS managed add-ons installed through aws_eks_addon.this.
  # coredns is excluded because aws_eks_addon.coredns already manages it.
  eks_addons = toset([
    "coredns",
    "metrics-server",
    "eks-node-monitoring-agent",
  ])
}
