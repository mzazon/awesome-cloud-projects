# versions.tf
# Provider requirements and version constraints

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

    # Random Provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Time Provider for time-based operations (if needed)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and modify as needed for your environment
  /*
  backend "s3" {
    # Example S3 backend configuration
    bucket         = "your-terraform-state-bucket"
    key            = "security-compliance-auditing/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
  */

  # Optional: Configure remote backend for Terraform Cloud
  /*
  cloud {
    organization = "your-organization"
    workspaces {
      name = "security-compliance-auditing"
    }
  }
  */
}

# Provider configuration blocks can be defined here or in main.tf
# The AWS provider is configured in main.tf with default tags

# Optional: Configure additional AWS provider for cross-region operations
# Uncomment if you need to deploy resources in multiple regions
/*
provider "aws" {
  alias  = "secondary"
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "security-compliance-auditing"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "security-compliance-auditing-lattice-guardduty"
      Region      = "secondary"
    }
  }
}
*/

# Version constraints explanation:
# - terraform >= 1.0: Ensures compatibility with modern Terraform features
# - aws ~> 5.0: Uses AWS provider version 5.x (latest major version with new features)
# - random ~> 3.1: Stable version for random resource generation
# - archive ~> 2.4: Latest stable version for archive operations
# - time ~> 0.9: For any time-based resource operations

# Terraform feature compatibility notes:
# - This configuration is compatible with Terraform 1.0+
# - Uses modern Terraform syntax and features
# - Supports both local and remote state management
# - Compatible with Terraform Cloud and Terraform Enterprise