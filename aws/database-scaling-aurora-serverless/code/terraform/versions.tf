# Terraform configuration for Aurora Serverless v2 Database Scaling
# Provider version requirements and backend configuration

terraform {
  required_version = ">= 1.5"
  
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

  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "aurora-serverless/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Aurora Serverless Database Scaling"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "database-scaling-strategies-aurora-serverless"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}