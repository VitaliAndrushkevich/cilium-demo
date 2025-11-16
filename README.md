# cilium-demo

Demo repository for cilium installation

Reuqirenments:

- Terraform
- AWS Cloud
- k3s
- cilium

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

1. Configure AWS credentials and Region.

2. Apply terraform condifuration by running `terraform apply`.

3. For convinience you might add aliases to quickly connect from one host to another one. This can be taken from terraform apply outputs.

```sh
alias bastion="${terraform output bastion_connection_string}"
alias cp="${terraform output controlplane_connection_string}"
alias node1="${terraform output node01_connection_string}"
alias node2="${terraform output node02_connection_string}
```

Following commands `bastion`, `cp`, `node1`, `node2` you can easily connect to the node.
