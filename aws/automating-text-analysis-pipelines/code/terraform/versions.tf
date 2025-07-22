# AWS Provider and Terraform version requirements
terraform {
  required_version = ">= 1.0"
  
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
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "natural-language-processing-pipelines"
      Environment = var.environment
      Recipe      = "amazon-comprehend-nlp-pipeline"
      ManagedBy   = "terraform"
    }
  }
}