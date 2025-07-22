# Terraform and Provider Version Constraints
# This file defines the required versions for Terraform and the AWS provider

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-iot-analytics-kinesis-iot-analytics"
    }
  }
}

# Configure the Random Provider for generating unique identifiers
provider "random" {
  # Configuration options
}