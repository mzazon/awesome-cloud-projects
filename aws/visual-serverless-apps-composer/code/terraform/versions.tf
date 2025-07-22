terraform {
  required_version = ">= 1.5.0"
  
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
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Visual Serverless Application"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "building-visual-serverless-applications"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}