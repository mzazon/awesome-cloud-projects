# Terraform version and provider requirements for PartyRock AI Applications with S3
# This configuration defines the minimum required versions for Terraform and AWS provider

terraform {
  # Require Terraform 1.0 or higher for stable feature support
  required_version = ">= 1.0"

  # Required provider configurations
  required_providers {
    # AWS provider for managing S3, CloudFront, and related services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region will be determined by:
  # 1. var.aws_region if specified
  # 2. AWS_REGION environment variable
  # 3. AWS CLI default region
  # 4. Provider default region
  region = var.aws_region

  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      Project             = "PartyRock AI Application"
      Environment         = var.environment
      ManagedBy          = "Terraform"
      Recipe             = "no-code-ai-applications-partyrock-s3"
      CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No additional configuration required for random provider
}