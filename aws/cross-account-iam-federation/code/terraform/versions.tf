# Terraform configuration for Advanced Cross-Account IAM Role Federation
# This file defines the required providers and their version constraints

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

  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "cross-account-iam/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider for the Security Account (default)
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Cross-Account-IAM-Federation"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Security"
    }
  }
}

# Provider alias for Production Account
provider "aws" {
  alias  = "production"
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${var.production_account_id}:role/OrganizationAccountAccessRole"
  }
  
  default_tags {
    tags = {
      Project     = "Cross-Account-IAM-Federation"
      Environment = "production"
      ManagedBy   = "Terraform"
      Purpose     = "Production"
    }
  }
}

# Provider alias for Development Account
provider "aws" {
  alias  = "development"
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${var.development_account_id}:role/OrganizationAccountAccessRole"
  }
  
  default_tags {
    tags = {
      Project     = "Cross-Account-IAM-Federation"
      Environment = "development"
      ManagedBy   = "Terraform"
      Purpose     = "Development"
    }
  }
}