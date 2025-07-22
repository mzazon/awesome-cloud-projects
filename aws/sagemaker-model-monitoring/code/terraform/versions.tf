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
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SageMaker Model Monitor"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "model-monitoring-drift-detection-sagemaker-model-monitor"
    }
  }
}