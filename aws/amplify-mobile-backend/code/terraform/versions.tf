# ==============================================================================
# Terraform and Provider Version Constraints
# 
# This file defines the minimum required versions for Terraform and the AWS 
# provider to ensure compatibility and access to necessary features for the
# mobile backend services infrastructure.
# ==============================================================================

terraform {
  # Minimum required Terraform version
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for cloud resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }

    # Archive provider for Lambda function code packaging
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.2.0"
    }
  }

  # Optional: Configure remote backend for state management
  # Uncomment and modify the backend configuration as needed
  # 
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "mobile-backend-services/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ==============================================================================
# AWS Provider Configuration
# ==============================================================================

provider "aws" {
  # AWS region will be determined by:
  # 1. AWS_REGION environment variable
  # 2. AWS CLI configuration
  # 3. EC2 instance metadata (if running on EC2)
  # 4. Default region specified here (optional)
  # region = var.aws_region

  # Default tags applied to all AWS resources
  default_tags {
    tags = {
      ManagedBy           = "Terraform"
      Project             = "mobile-backend-services-amplify"
      TerraformWorkspace  = terraform.workspace
      DeploymentDate      = timestamp()
    }
  }

  # Provider features and configuration
  # Uncomment and configure as needed
  
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/terraform-role"
  #   session_name = "terraform-session"
  # }

  # shared_credentials_files = ["~/.aws/credentials"]
  # profile                  = "default"
}

# ==============================================================================
# Random Provider Configuration
# ==============================================================================

provider "random" {
  # No specific configuration required for random provider
}

# ==============================================================================
# Archive Provider Configuration
# ==============================================================================

provider "archive" {
  # No specific configuration required for archive provider
}

# ==============================================================================
# Version Compatibility Notes
# ==============================================================================

# Terraform Version Requirements:
# - Terraform >= 1.5.0: Required for the latest language features and
#   stability improvements used in this configuration
#
# AWS Provider Version Requirements:
# - AWS Provider >= 5.0.0: Required for the latest AWS service features
#   including updated AppSync resources, Cognito enhancements, and
#   improved DynamoDB configurations
# - AWS Provider < 6.0.0: Upper bound to prevent breaking changes from
#   future major version releases
#
# Random Provider Version Requirements:
# - Random Provider >= 3.1.0: Required for stable random ID generation
#   used in resource naming
#
# Archive Provider Version Requirements:
# - Archive Provider >= 2.2.0: Required for reliable Lambda function
#   code packaging and deployment

# ==============================================================================
# Terraform Workspace Support
# ==============================================================================

# This configuration supports Terraform workspaces for environment separation.
# To use workspaces:
#
# 1. Create workspaces for different environments:
#    terraform workspace new dev
#    terraform workspace new staging
#    terraform workspace new prod
#
# 2. Switch between workspaces:
#    terraform workspace select dev
#
# 3. The current workspace name is available as terraform.workspace
#    and is automatically included in default tags

# ==============================================================================
# Backend Configuration Examples
# ==============================================================================

# Example S3 Backend Configuration:
# This provides state file storage in S3 with DynamoDB locking
# 
# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "mobile-backend/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-locks"
#     
#     # Optional: Use workspace-specific state files
#     workspace_key_prefix = "environments"
#   }
# }

# Example Terraform Cloud Backend Configuration:
# This provides state management and remote execution with Terraform Cloud
#
# terraform {
#   cloud {
#     organization = "my-organization"
#     
#     workspaces {
#       name = "mobile-backend-services"
#     }
#   }
# }

# Example Local Backend Configuration:
# This keeps state files locally (default behavior)
# Not recommended for team environments
#
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# ==============================================================================
# Provider Feature Flags and Experimental Features
# ==============================================================================

# The AWS provider supports various feature flags for experimental features
# or to maintain backward compatibility. Uncomment and configure as needed:

# provider "aws" {
#   # S3 use path-style addressing (for compatibility with S3-compatible services)
#   s3_use_path_style = false
#   
#   # Skip metadata API check (useful in restricted environments)
#   skip_metadata_api_check = false
#   
#   # Skip region validation (allows custom/private regions)
#   skip_region_validation = false
#   
#   # Skip requesting account ID (for limited permission scenarios)
#   skip_requesting_account_id = false
#   
#   # Skip credentials validation
#   skip_credentials_validation = false
# }

# ==============================================================================
# Development and Testing Considerations
# ==============================================================================

# For development and testing environments, consider these optimizations:
#
# 1. Use shorter-lived credentials with AWS CLI profiles
# 2. Enable detailed logging for troubleshooting:
#    export TF_LOG=DEBUG
# 3. Use local state for rapid iteration (not recommended for production)
# 4. Consider using AWS LocalStack for local testing
# 5. Use terraform plan frequently to preview changes
# 6. Use terraform fmt and terraform validate for code quality

# ==============================================================================
# Production Deployment Considerations
# ==============================================================================

# For production deployments, ensure:
#
# 1. Remote state backend is configured and secured
# 2. State locking is enabled (DynamoDB with S3 backend)
# 3. Provider versions are pinned to specific versions
# 4. Default tags include compliance and governance information
# 5. Assume role is used for cross-account deployments
# 6. Sensitive outputs are properly marked as sensitive
# 7. Regular state file backups are configured
# 8. Plan files are reviewed before apply operations