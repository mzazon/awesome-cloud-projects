# Terraform and AWS Provider version constraints
terraform {
  required_version = ">= 1.5"

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

# Configure the AWS Provider
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "global-ecommerce-aurora-dsql"
      ManagedBy   = "terraform"
    }
  }
}

# Additional provider for multi-region resources if needed
provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "global-ecommerce-aurora-dsql"
      ManagedBy   = "terraform"
    }
  }
}