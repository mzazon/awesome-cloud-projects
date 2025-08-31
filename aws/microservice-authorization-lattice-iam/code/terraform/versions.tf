# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and AWS provider

terraform {
  required_version = ">= 1.5.0"
  
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

# Configure the AWS Provider with default tags for all resources
provider "aws" {
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Purpose     = "MicroserviceAuth"
      Recipe      = "microservice-authorization-lattice-iam"
    }
  }
}