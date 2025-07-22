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
  default_tags {
    tags = {
      Project     = "mlops-sagemaker-pipelines"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "end-to-end-mlops-sagemaker-pipelines"
    }
  }
}