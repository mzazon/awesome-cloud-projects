# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and the AWS provider

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project           = var.project_name
      Environment       = var.environment
      ManagedBy        = "Terraform"
      CostCenter       = var.cost_center
      CreatedBy        = "advanced-monitoring-recipe"
      LastUpdated      = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}