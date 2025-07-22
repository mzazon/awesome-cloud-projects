# Provider version requirements for AWS automated data ingestion pipelines
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
      Project     = "DataIngestionPipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "automated-data-ingestion-pipelines-opensearch-eventbridge"
    }
  }
}