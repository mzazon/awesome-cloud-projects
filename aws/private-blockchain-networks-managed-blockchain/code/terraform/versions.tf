terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Private Blockchain Network"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "private-blockchain-networks-amazon-managed-blockchain"
    }
  }
}

provider "random" {}