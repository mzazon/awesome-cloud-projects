# ==============================================================================
# Provider Requirements and Configuration
# ==============================================================================

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
  # AWS Provider configuration
  # Region and credentials should be configured via:
  # - AWS CLI configuration
  # - Environment variables (AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  # - IAM roles for EC2/ECS/Lambda
  # - AWS SSO
  
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "BusinessAutomation"
      Repository  = "recipes"
      Recipe      = "automated-business-task-scheduling-eventbridge-scheduler-lambda"
      ManagedBy   = "Terraform"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # Random provider for generating unique suffixes
}

# Configure the Archive Provider  
provider "archive" {
  # Archive provider for creating Lambda deployment packages
}