# Terraform and Provider Version Requirements
terraform {
  required_version = ">= 1.0"
  
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

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "basic-log-monitoring"
      Recipe      = "basic-log-monitoring-cloudwatch-sns"
      ManagedBy   = "terraform"
    }
  }
}