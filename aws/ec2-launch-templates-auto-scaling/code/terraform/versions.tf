# versions.tf
# Provider requirements and Terraform version constraints

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "EC2-Auto-Scaling-Demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "ec2-launch-templates-auto-scaling"
    }
  }
}

# Configure the Random Provider for generating unique resource names
provider "random" {}