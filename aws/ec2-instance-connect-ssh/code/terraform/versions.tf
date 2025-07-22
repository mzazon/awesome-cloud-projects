# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and stability across deployments

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

# AWS Provider Configuration
# Configure the AWS provider with the specified region
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "EC2InstanceConnect"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "ec2-instance-connect-secure-ssh-access"
    }
  }
}

# Random Provider Configuration
# Used for generating unique resource names
provider "random" {}