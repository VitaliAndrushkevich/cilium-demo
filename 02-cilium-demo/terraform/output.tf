output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_endpoint_for_cilium" {
  value = trim(aws_eks_cluster.this.endpoint, "https://")
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region eu-north-1 --name ${aws_eks_cluster.this.name}"
}

output "nlb_controller_role_arn" {
  description = "IRSA role ARN for the kube-system/aws-load-balancer-controller service account."
  value       = one(aws_iam_role.nlb_controller[*].arn)
}
