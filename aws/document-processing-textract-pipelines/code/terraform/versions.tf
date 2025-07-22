terraform {
  required_version = ">= 1.5"
  
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
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project     = "DocumentProcessingPipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}