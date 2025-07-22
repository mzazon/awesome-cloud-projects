# Terraform and Provider Version Requirements
# Event-Driven Architecture with Amazon EventBridge

terraform {
  # Terraform version requirement
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }

    # Local provider for creating local files (Lambda source code)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Archive provider for creating ZIP files for Lambda deployment
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Backend configuration (uncomment and configure as needed)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "event-driven-architecture/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# Configure the AWS Provider
provider "aws" {
  # AWS region is typically set via environment variable AWS_DEFAULT_REGION
  # or AWS CLI configuration, but can be explicitly set here if needed
  # region = "us-east-1"

  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "EventDrivenArchitecture"
      Repository  = "recipes"
      Recipe      = "event-driven-architectures-with-eventbridge"
      CreatedBy   = "Terraform"
      LastUpdated = timestamp()
    }
  }

  # Optional: Assume role configuration for cross-account deployments
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT_ID:role/TerraformRole"
  #   session_name = "TerraformSession"
  # }
}

# Configure the Random Provider
provider "random" {
  # No additional configuration required for random provider
}

# Configure the Local Provider
provider "local" {
  # No additional configuration required for local provider
}

# Configure the Archive Provider
provider "archive" {
  # No additional configuration required for archive provider
}

# Provider feature flags and configuration
terraform {
  # Enable experimental features if needed
  # experiments = []

  # Provider metadata for enhanced functionality
  provider_meta "aws" {
    # Enable detailed error messages
    module_name = "event-driven-architecture-eventbridge"
  }
}

# Optional: Configure provider aliases for multi-region deployments
# provider "aws" {
#   alias  = "us_west_2"
#   region = "us-west-2"
#   
#   default_tags {
#     tags = {
#       Terraform = "true"
#       Project   = "EventDrivenArchitecture"
#       Region    = "us-west-2"
#     }
#   }
# }

# Optional: Configure provider for AWS Organizations management
# provider "aws" {
#   alias  = "management"
#   region = "us-east-1"
#   
#   assume_role {
#     role_arn = "arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/OrganizationAccountAccessRole"
#   }
# }