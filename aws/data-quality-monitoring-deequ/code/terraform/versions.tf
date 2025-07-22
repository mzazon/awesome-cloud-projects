# versions.tf
# Terraform version and provider requirements for real-time data quality monitoring with Deequ on EMR

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

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DeeQuDataQualityMonitoring"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-data-quality-monitoring-deequ-emr"
    }
  }
}