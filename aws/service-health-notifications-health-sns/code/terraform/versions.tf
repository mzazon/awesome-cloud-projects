# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure consistent deployments across different environments

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS Provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = "AWS Health Notifications"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "service-health-notifications-health-sns"
    }
  }
}