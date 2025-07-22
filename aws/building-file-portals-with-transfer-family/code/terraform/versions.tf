# ==========================================================================
# TERRAFORM PROVIDER VERSIONS AND REQUIREMENTS
# ==========================================================================
# This file defines the required Terraform version and provider constraints
# for the AWS Transfer Family Web App secure file portal infrastructure.

# ==========================================================================
# TERRAFORM VERSION REQUIREMENTS
# ==========================================================================

terraform {
  # Require Terraform version 1.0 or higher for stability and modern features
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0"
    }
    
    # Random Provider - Used for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure for production deployments
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "transfer-family-web-app/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# ==========================================================================
# AWS PROVIDER CONFIGURATION
# ==========================================================================

provider "aws" {
  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      ManagedBy           = "Terraform"
      Project             = "SecureFilePortal"
      Recipe              = "secure-self-service-file-portals-transfer-family-web-apps"
      TerraformWorkspace  = terraform.workspace
      DeploymentTimestamp = timestamp()
    }
  }

  # Provider-level configuration
  # Region is typically set via AWS_DEFAULT_REGION environment variable
  # or AWS profile configuration
  
  # Uncomment and set specific region if needed
  # region = "us-east-1"
  
  # Uncomment and set specific profile if needed
  # profile = "default"
  
  # Uncomment for cross-account deployments
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  #   session_name = "terraform-transfer-family-deployment"
  # }
}

# ==========================================================================
# RANDOM PROVIDER CONFIGURATION
# ==========================================================================

provider "random" {
  # No specific configuration required for random provider
}

# ==========================================================================
# PROVIDER FEATURE FLAGS
# ==========================================================================

# AWS Provider experimental features
# Uncomment as needed for specific feature requirements

# Enable S3 Transfer Acceleration support
# provider "aws" {
#   s3_use_path_style = false
# }

# ==========================================================================
# DATA SOURCES FOR PROVIDER VALIDATION
# ==========================================================================

# Validate AWS provider configuration and permissions
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Validate required AWS services are available in the region
data "aws_service" "transfer" {
  service_id = "transfer"
  region     = data.aws_region.current.name
}

data "aws_service" "s3" {
  service_id = "s3"
  region     = data.aws_region.current.name
}

data "aws_service" "sso" {
  service_id = "sso"
  region     = data.aws_region.current.name
}

# ==========================================================================
# PROVIDER VERSION VALIDATION
# ==========================================================================

# Local values for provider version validation
locals {
  # Minimum required provider versions
  min_aws_provider_version    = "5.30.0"
  min_random_provider_version = "3.4.0"
  min_terraform_version       = "1.0.0"
  
  # Current provider versions (for informational purposes)
  aws_provider_version    = "~> 5.30"
  random_provider_version = "~> 3.4"
  
  # Service availability validation
  required_services = [
    "transfer",  # AWS Transfer Family
    "s3",        # Amazon S3
    "sso",       # AWS Single Sign-On (IAM Identity Center)
    "iam",       # AWS Identity and Access Management
    "logs"       # Amazon CloudWatch Logs
  ]
  
  # Region-specific feature validation
  transfer_family_regions = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
    "ap-southeast-1", "ap-southeast-2", "ap-northeast-1",
    "ap-northeast-2", "ap-south-1", "ca-central-1",
    "sa-east-1"
  ]
  
  # Validate current region supports Transfer Family
  region_supported = contains(local.transfer_family_regions, data.aws_region.current.name)
}

# Validation checks using check blocks (Terraform 1.5+)
check "aws_region_supports_transfer_family" {
  assert {
    condition = local.region_supported
    error_message = "AWS Transfer Family Web Apps is not available in region ${data.aws_region.current.name}. Please deploy in a supported region: ${join(", ", local.transfer_family_regions)}"
  }
}

check "aws_account_permissions" {
  assert {
    condition = data.aws_caller_identity.current.account_id != ""
    error_message = "Unable to determine AWS account ID. Please check AWS credentials and permissions."
  }
}

# ==========================================================================
# PROVIDER ALIASES (for multi-region deployments)
# ==========================================================================

# Uncomment for multi-region deployments
# Example: Deploy monitoring resources in a different region

# provider "aws" {
#   alias  = "monitoring"
#   region = "us-east-1"  # CloudWatch and monitoring resources
#   
#   default_tags {
#     tags = {
#       ManagedBy          = "Terraform"
#       Project            = "SecureFilePortal"
#       Region             = "monitoring"
#       TerraformWorkspace = terraform.workspace
#     }
#   }
# }

# provider "aws" {
#   alias  = "backup"
#   region = "us-west-2"  # Backup and disaster recovery
#   
#   default_tags {
#     tags = {
#       ManagedBy          = "Terraform"
#       Project            = "SecureFilePortal"
#       Region             = "backup"
#       TerraformWorkspace = terraform.workspace
#     }
#   }
# }

# ==========================================================================
# EXPERIMENTAL FEATURES
# ==========================================================================

# Uncomment to enable Terraform experimental features as needed

# terraform {
#   experiments = [
#     # Enable module_variable_optional_attrs experiment
#     module_variable_optional_attrs
#   ]
# }