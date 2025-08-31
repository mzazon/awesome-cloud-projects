# ===============================================
# Terraform and Provider Version Requirements
# Simple Configuration Management with Parameter Store and CloudShell
# ===============================================

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Optional: Terraform Cloud/Enterprise backend configuration
  # Uncomment and configure if using remote state storage
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "parameter-store/terraform.tfstate"
  #   region = "us-east-1"
  #   
  #   # Optional: DynamoDB table for state locking
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}

# ===============================================
# AWS Provider Configuration
# ===============================================

provider "aws" {
  # Default tags applied to all resources managed by this provider
  default_tags {
    tags = {
      ManagedBy          = "Terraform"
      TerraformWorkspace = terraform.workspace
      Recipe             = "simple-configuration-management-parameter-store-cloudshell"
      CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
    }
  }

  # Optional: Assume role configuration for cross-account access
  # Uncomment and configure if deploying to a different AWS account
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  #   session_name = "TerraformParameterStoreDeployment"
  # }
}

# ===============================================
# Random Provider Configuration
# ===============================================

provider "random" {
  # No specific configuration required for random provider
}