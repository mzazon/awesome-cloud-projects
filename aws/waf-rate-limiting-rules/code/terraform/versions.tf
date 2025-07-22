# Terraform and provider version requirements
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
  # Provider configuration will be sourced from environment variables
  # AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # or AWS profiles and IAM roles
  
  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "WAF-Rate-Limiting"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "web-application-firewalls-aws-waf-rate-limiting-rules"
    }
  }
}

# AWS provider alias for us-east-1 (required for CloudFront WAF)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project     = "WAF-Rate-Limiting"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "web-application-firewalls-aws-waf-rate-limiting-rules"
    }
  }
}