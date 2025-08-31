# Terraform configuration for AWS Service Quota Monitoring
# This file defines the required providers and their version constraints

terraform {
  required_version = ">= 1.5.0"

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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ServiceQuotaMonitoring"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "service-quota-monitoring-cloudwatch"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}