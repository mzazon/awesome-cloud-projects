terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project             = "HPC-Batch-Spot"
      Environment         = var.environment
      ManagedBy          = "Terraform"
      Recipe             = "optimizing-high-performance-computing-workloads-with-aws-batch-and-spot-instances"
      CostCenter         = var.cost_center
      Owner              = var.owner
    }
  }
}