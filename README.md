# cilium-demo

Demo repository for cilium installation

Reuqirenments:

- Terraform
- AWS Cloud
- k3s
- cilium

Labs:

- [01](./01-cilium-demo/) Cilium installation on k3s with kube-proxy replacement, l2 anouncement and cilium ingress enablement.

Initial configuration:

1. Create S3 bucket that being used for storing terraform state.

2. Configure backend configuration.

```hcl
terraform {
  backend "s3" {
    bucket       = "cilium-demo-s3-bucket"
    region       = "eu-north-1"
    key          = "cilium-demo-01/terraform.tfstate"
    use_lockfile = true
  }
}
```

3. Configure AWS credentials and Region.
