# Terraform and provider version requirements
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
    
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "distributed-tracing-demo"
      Environment = var.environment
      CreatedBy   = "terraform"
      Recipe      = "distributed-tracing-x-ray-eventbridge"
    }
  }
}