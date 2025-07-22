# =============================================================================
# Terraform and Provider Version Requirements
# Database Monitoring Dashboards with CloudWatch
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure based on your requirements
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "database-monitoring/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# Configure the AWS Provider
provider "aws" {
  # Configuration options can be set via environment variables:
  # - AWS_REGION
  # - AWS_ACCESS_KEY_ID  
  # - AWS_SECRET_ACCESS_KEY
  # - AWS_PROFILE (for named profiles)
  
  # Alternatively, you can specify them here:
  # region  = "us-east-1"
  # profile = "default"

  # Default tags applied to all resources
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "database-monitoring-dashboards"
      Repository  = "recipes"
      Component   = "infrastructure"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No configuration needed for the random provider
}