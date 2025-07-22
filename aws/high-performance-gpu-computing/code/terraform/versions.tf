# Terraform and provider version requirements for GPU-accelerated workloads
# This configuration ensures compatibility with the latest AWS provider features
# and Terraform functionality required for GPU instance management

terraform {
  required_version = ">= 1.6"
  
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

# Configure the AWS Provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = "GPU-Accelerated-Workloads"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "GPU-Computing"
    }
  }
}