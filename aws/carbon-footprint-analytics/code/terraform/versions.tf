# Terraform configuration for AWS Sustainability Intelligence Dashboard
# This file specifies the required providers and minimum versions

terraform {
  required_version = ">= 1.6.0"
  
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
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = {
      Project     = "SustainabilityIntelligence"
      Environment = var.environment
      Purpose     = "Carbon footprint analytics and cost optimization"
      CreatedBy   = "Terraform"
      Recipe      = "intelligent-sustainability-dashboards-aws-sustainability-hub-quicksight"
    }
  }
}