# Terraform and provider version requirements for CloudFront and WAF deployment
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
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "secure-content-delivery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "content-delivery-cloudfront-waf"
    }
  }
}

# AWS Provider for us-east-1 (required for CloudFront WAF)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "secure-content-delivery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "content-delivery-cloudfront-waf"
    }
  }
}