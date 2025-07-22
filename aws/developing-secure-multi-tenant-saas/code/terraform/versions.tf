# Terraform and provider version requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy          = "Terraform"
      Recipe             = "multi-tenant-saas-amplify"
      TerraformWorkspace = terraform.workspace
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for packaging Lambda functions
provider "archive" {}