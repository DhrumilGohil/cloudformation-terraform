provider "aws" {
  region     = var.aws_region
}
terraform {
   cloud {
    organization = "dhrumil-test-org"

    workspaces {
      name = "test-macon"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}
