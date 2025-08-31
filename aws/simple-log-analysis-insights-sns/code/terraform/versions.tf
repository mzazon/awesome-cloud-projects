# Terraform version and provider requirements for log analysis infrastructure
# This file defines the minimum Terraform version and AWS provider version
# required to deploy the CloudWatch Logs Insights and SNS alert solution

terraform {
  # Require Terraform 1.0 or newer for stable language features
  required_version = ">= 1.0"

  # AWS Provider with CloudWatch Logs Insights and EventBridge support
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Archive provider for Lambda function packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider with default tags for resource management
provider "aws" {
  default_tags {
    tags = {
      Project     = "simple-log-analysis"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "simple-log-analysis-insights-sns"
    }
  }
}