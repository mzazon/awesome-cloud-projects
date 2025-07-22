# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

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
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "ApplicationDiscoveryService"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "application-discovery-assessment-aws-application-discovery-service"
    }
  }
}

# Random Provider for generating unique identifiers
provider "random" {}