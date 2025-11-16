module "vpc" {
  source  = "ViktorUJ/vpc/aws"
  version = "~>1.0"

  tags_default = {
    "Author"    = "Vitali Andrushkevich <andrushkevich.vitaly@gmail.com>"
    "Terraform" = "true"
  }

  vpc = {
    name = "cilium-demo-vpc"
    cidr = "10.10.0.0/16"
  }

  subnets = {
    public = {
      "cilium-public-bastion" = {
        name        = "cilium-demo-public"
        cidr        = "10.10.1.0/24"
        az          = "eu-north-1a"
        nat_gateway = "DEFAULT"
      }
    }
    private = {
      "cilium-private-k8s" = {
        name        = "cilium-private-k8s"
        cidr        = "10.10.11.0/24"
        az          = "eu-north-1a"
        nat_gateway = "SINGLE"
        tags        = {}
      }
    }
  }
}
