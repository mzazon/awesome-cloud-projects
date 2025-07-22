# Terraform and Provider Version Requirements
# This file defines the minimum versions for Terraform and required providers
# to ensure compatibility and access to necessary features

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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AudioProcessingPipeline"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "audio-processing-pipelines-aws-elemental-mediaconvert"
    }
  }
}