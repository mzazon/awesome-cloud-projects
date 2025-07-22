# Terraform provider version constraints for AWS AppSync real-time data synchronization
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

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = "AppSync Real-time Tasks"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "AppSync Tutorial"
    }
  }
}