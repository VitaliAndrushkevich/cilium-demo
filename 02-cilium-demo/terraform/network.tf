module "vpc" {
  source  = "ViktorUJ/vpc/aws"
  version = "~>1.0"

  tags_default = {
    "Author"    = "Vitali Andrushkevich <andrushkevich.vitaly@gmail.com>"
    "Terraform" = "true"
  }

  vpc = {
    name = "cilium-demo-02-vpc"
    cidr = "10.20.0.0/16"
  }

  subnets = {
    public = {
      "cilium-public-bastion" = {
        name        = "cilium-demo-02-public"
        cidr        = "10.20.1.0/24"
        az          = "eu-north-1a"
        nat_gateway = "DEFAULT"
      }
    }
    private = {
      # EKS requires subnets in at least two Availability Zones for the
      # control plane cross-account ENIs, even for a single-node demo.
      "cilium-private-eks-a" = {
        name        = "cilium-private-eks-a"
        cidr        = "10.20.11.0/24"
        az          = "eu-north-1a"
        nat_gateway = "SINGLE"
        tags        = {}
      }
      "cilium-private-eks-b" = {
        name        = "cilium-private-eks-b"
        cidr        = "10.20.12.0/24"
        az          = "eu-north-1b"
        nat_gateway = "SINGLE"
        tags        = {}
      }
    }
  }
}
