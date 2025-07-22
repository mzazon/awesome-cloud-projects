# Provider version requirements for AWS Terraform resources
# This configuration ensures consistent provider versions across deployments

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Primary region for Aurora DSQL cluster and Lambda deployment
  region = var.aws_region

  # Common tags applied to all resources
  default_tags {
    tags = {
      Project     = "real-time-task-management"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "real-time-collaborative-task-management-aurora-dsql-eventbridge"
    }
  }
}

# Secondary region provider for multi-region Aurora DSQL setup
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  # Apply same default tags to secondary region resources
  default_tags {
    tags = {
      Project     = "real-time-task-management"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "real-time-collaborative-task-management-aurora-dsql-eventbridge"
      Region      = "secondary"
    }
  }
}