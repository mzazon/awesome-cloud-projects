# Terraform and Provider Version Requirements

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Infrastructure Monitoring"
      ManagedBy   = "Terraform"
      Recipe      = "infrastructure-monitoring-cloudtrail-config-systems-manager"
      Environment = var.environment
    }
  }
}