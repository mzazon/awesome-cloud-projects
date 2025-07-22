terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS provider with the management account credentials
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CloudFormation-StackSets-Multi-Account"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Organization-Wide-Governance"
    }
  }
}

# Random provider for generating unique resource names
provider "random" {}

# Archive provider for Lambda function packaging
provider "archive" {}