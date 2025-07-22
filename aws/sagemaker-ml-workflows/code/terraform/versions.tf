# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
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
      version = "~> 2.4"
    }
  }
}

# Default AWS provider configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = "ML-Pipeline-SageMaker-StepFunctions"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}