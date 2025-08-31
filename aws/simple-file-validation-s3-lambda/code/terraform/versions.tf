# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider - Official AWS provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Archive Provider - For creating ZIP files for Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Local Provider - For creating local files (Lambda function code)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # Optional: Configure Terraform backend for state management
  # Uncomment and configure the backend block below for production deployments
  # 
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "file-validation/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================

# AWS Provider configuration with default tags and regional settings
provider "aws" {
  region = var.aws_region

  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      Project           = var.project_name
      Environment       = var.environment
      ManagedBy         = "terraform"
      Recipe            = "simple-file-validation-s3-lambda"
      TerraformWorkspace = terraform.workspace
    }
  }
}

# Archive Provider - No additional configuration required
provider "archive" {}

# Random Provider - No additional configuration required
provider "random" {}

# Local Provider - No additional configuration required
provider "local" {}