# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = {
      Project     = "AutomatedDataAnalysis"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "bedrock-agentcore-data-analysis"
    }
  }
}