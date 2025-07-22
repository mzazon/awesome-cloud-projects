# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and AWS provider

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

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Terraform   = "true"
      Environment = var.environment
      Project     = var.project_name
      Recipe      = "real-time-data-processing-kinesis-data-firehose"
    }
  }
}

# Random Provider Configuration
provider "random" {
  # Configuration options
}

# Archive Provider Configuration
provider "archive" {
  # Configuration options
}