terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Author    = "andrushkevich.vitaly@gmail.com"
      Terraform = "true"
      Lab       = "Cilium Demo 02"
      GitHub    = "https://github.com/VitaliAndrushkevich/cilium-demo"
    }
  }
}
