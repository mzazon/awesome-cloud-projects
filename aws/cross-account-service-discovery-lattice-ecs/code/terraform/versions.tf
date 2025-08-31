# Terraform version and provider requirements for cross-account service discovery with VPC Lattice and ECS
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

# AWS Provider configuration for primary account (Account A - Producer)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cross-account-service-discovery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "vpc-lattice-ecs-cross-account"
    }
  }
}

# AWS Provider configuration for secondary account (Account B - Consumer)
# This provider alias is used when resources need to be created in Account B
provider "aws" {
  alias  = "account_b"
  region = var.aws_region

  # Assume role in Account B for cross-account resource creation
  assume_role {
    role_arn = var.account_b_assume_role_arn
  }

  default_tags {
    tags = {
      Project     = "cross-account-service-discovery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "vpc-lattice-ecs-cross-account"
    }
  }
}