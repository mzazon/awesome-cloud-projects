# ==============================================================================
# Terraform and Provider Version Constraints
# ==============================================================================

terraform {
  # Require Terraform version 1.0 or higher for stability and modern features
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

# ==============================================================================
# AWS Provider Configuration
# ==============================================================================

provider "aws" {
  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      Project            = "analytics-ready-data-storage"
      Recipe             = "s3-tables-analytics"
      TerraformManaged   = "true"
      ProviderVersion    = "aws-~>5.70"
      TerraformVersion   = "~>1.0"
      CreatedBy          = "terraform"
      LastUpdated        = timestamp()
    }
  }

  # Skip metadata API check for improved performance
  skip_metadata_api_check = true

  # Skip requesting AWS account ID for performance
  skip_requesting_account_id = false

  # Skip region validation for custom/new regions
  skip_region_validation = false

  # Skip credential validation for automated environments
  skip_credentials_validation = false
}

# ==============================================================================
# Random Provider Configuration
# ==============================================================================

provider "random" {
  # No specific configuration required for random provider
}