# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for core AWS services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Local provider for creating local files (Lambda code)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }

    # Archive provider for creating ZIP files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and modify the backend configuration below for production use
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "resilience-hub/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region is typically set via environment variable AWS_REGION
  # or through AWS CLI configuration
  
  # Optional: Specify default tags that will be applied to all resources
  default_tags {
    tags = {
      Project     = "resilience-monitoring"
      ManagedBy   = "terraform"
      Environment = var.environment
      Owner       = "platform-team"
    }
  }

  # Optional: Skip validation of credentials during terraform init
  # skip_credentials_validation = true
  
  # Optional: Skip getting region from EC2 metadata service
  # skip_region_validation = true
  
  # Optional: Skip requesting Account ID (useful for CI/CD)
  # skip_requesting_account_id = true
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}

# Configure the Local Provider
provider "local" {
  # No specific configuration required
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration required
}