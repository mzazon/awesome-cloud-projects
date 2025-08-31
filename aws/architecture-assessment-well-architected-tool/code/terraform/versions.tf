# Terraform and provider version constraints
terraform {
  required_version = ">= 1.6"

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

# Configure the AWS Provider
provider "aws" {
  # Provider configuration can be customized via variables
  default_tags {
    tags = {
      Environment   = var.environment
      Project       = var.project_name
      ManagedBy     = "terraform"
      Purpose       = "well-architected-assessment"
      CostCenter    = var.cost_center
      Owner         = var.owner
    }
  }
}