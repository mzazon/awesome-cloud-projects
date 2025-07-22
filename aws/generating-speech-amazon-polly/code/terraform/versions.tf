# ========================================
# Terraform and Provider Version Constraints
# ========================================
# This file defines version constraints for Terraform and all required providers
# to ensure consistent and predictable deployments across different environments.

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for Amazon Web Services resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Time Provider for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

    # Archive Provider for creating ZIP files (if Lambda function is enabled)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Template Provider for rendering configuration templates
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Local Provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Null Provider for null resources and provisioners
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Optional: Configure Terraform Cloud or remote backend
  # Uncomment and configure the backend block below if using remote state management
  
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "polly-tts/terraform.tfstate"
  #   region = "us-east-1"
  #   
  #   # Enable state locking and consistency checking
  #   dynamodb_table = "your-terraform-locks-table"
  #   encrypt        = true
  #   
  #   # Optional: Use assume role for cross-account access
  #   # assume_role {
  #   #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  #   # }
  # }

  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "polly-tts-infrastructure"
  #   }
  # }
}

# ========================================
# AWS Provider Configuration
# ========================================
# Main AWS provider configuration with default tags and region settings

provider "aws" {
  # AWS region will be set via variable or environment variable
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project             = "Amazon-Polly-TTS"
      Environment         = var.environment
      ManagedBy          = "Terraform"
      Recipe             = "text-to-speech-applications-amazon-polly"
      TerraformVersion   = "~> 1.0"
      AWSProviderVersion = "~> 5.0"
      DeploymentDate     = formatdate("YYYY-MM-DD", timestamp())
      CostCenter         = var.cost_center
      ProjectOwner       = var.project_owner
      BusinessUnit       = var.business_unit
    }
  }

  # Optional: Configure assume role for cross-account access
  # assume_role {
  #   role_arn = var.assume_role_arn
  # }

  # Optional: Configure AWS CLI profile
  # profile = var.aws_profile

  # Optional: Configure shared credentials file
  # shared_credentials_file = var.shared_credentials_file

  # Optional: Configure custom CA bundle
  # ca_bundle = var.ca_bundle

  # Enable detailed error messages for debugging
  # skip_region_validation = false
  # skip_credentials_validation = false
  # skip_metadata_api_check = false
}

# ========================================
# Alternative AWS Provider for Cross-Region Resources
# ========================================
# Secondary AWS provider for cross-region resources like replication

provider "aws" {
  alias  = "backup"
  region = var.backup_region

  default_tags {
    tags = {
      Project             = "Amazon-Polly-TTS"
      Environment         = var.environment
      ManagedBy          = "Terraform"
      Recipe             = "text-to-speech-applications-amazon-polly"
      Role               = "backup-region"
      TerraformVersion   = "~> 1.0"
      AWSProviderVersion = "~> 5.0"
      DeploymentDate     = formatdate("YYYY-MM-DD", timestamp())
      CostCenter         = var.cost_center
      ProjectOwner       = var.project_owner
      BusinessUnit       = var.business_unit
    }
  }
}

# ========================================
# Random Provider Configuration
# ========================================
# Configuration for random provider used for generating unique names

provider "random" {
  # No specific configuration needed for random provider
}

# ========================================
# Time Provider Configuration
# ========================================
# Configuration for time provider used for time-based resources

provider "time" {
  # No specific configuration needed for time provider
}

# ========================================
# Archive Provider Configuration
# ========================================
# Configuration for archive provider used for creating ZIP files

provider "archive" {
  # No specific configuration needed for archive provider
}

# ========================================
# Template Provider Configuration
# ========================================
# Configuration for template provider used for rendering templates

provider "template" {
  # No specific configuration needed for template provider
}

# ========================================
# Local Provider Configuration
# ========================================
# Configuration for local provider used for local file operations

provider "local" {
  # No specific configuration needed for local provider
}

# ========================================
# Null Provider Configuration
# ========================================
# Configuration for null provider used for null resources

provider "null" {
  # No specific configuration needed for null provider
}

# ========================================
# Provider Version Constraints Explanation
# ========================================
# The following version constraints are used:
#
# AWS Provider (~> 5.0):
# - Uses AWS Provider version 5.x.x
# - Allows minor version updates (5.1.0, 5.2.0, etc.)
# - Prevents major version updates (6.0.0)
# - Ensures compatibility with latest AWS services and features
#
# Random Provider (~> 3.4):
# - Uses Random Provider version 3.4.x
# - Allows patch version updates (3.4.1, 3.4.2, etc.)
# - Prevents minor version updates (3.5.0)
# - Provides stable random resource generation
#
# Time Provider (~> 0.9):
# - Uses Time Provider version 0.9.x
# - Allows patch version updates within 0.9.x series
# - Provides time-based resource management
#
# Archive Provider (~> 2.4):
# - Uses Archive Provider version 2.4.x
# - Allows patch version updates within 2.4.x series
# - Provides ZIP file creation capabilities
#
# Template Provider (~> 2.2):
# - Uses Template Provider version 2.2.x
# - Allows patch version updates within 2.2.x series
# - Provides template rendering capabilities
#
# Local Provider (~> 2.4):
# - Uses Local Provider version 2.4.x
# - Allows patch version updates within 2.4.x series
# - Provides local file operations
#
# Null Provider (~> 3.2):
# - Uses Null Provider version 3.2.x
# - Allows patch version updates within 3.2.x series
# - Provides null resource and provisioner capabilities

# ========================================
# Terraform Version Constraints Explanation
# ========================================
# Terraform Version (>= 1.0):
# - Requires Terraform version 1.0 or later
# - Ensures access to modern Terraform features
# - Provides improved state management and planning
# - Supports enhanced type validation and error messages
# - Includes better provider dependency management

# ========================================
# Best Practices for Version Management
# ========================================
# 1. Pin provider versions to prevent unexpected changes
# 2. Use semantic versioning constraints (~> x.y) for flexibility
# 3. Regularly update provider versions for security patches
# 4. Test version updates in development environments first
# 5. Document version change reasons in commit messages
# 6. Use .terraform.lock.hcl file to lock exact versions
# 7. Consider using Terraform Cloud for version management
# 8. Set up automated security scanning for provider updates

# ========================================
# State Management Configuration
# ========================================
# The commented backend configurations above provide options for:
#
# S3 Backend:
# - Remote state storage in Amazon S3
# - State locking with DynamoDB
# - Encryption at rest
# - Cross-account access support
#
# Terraform Cloud Backend:
# - Hosted state management
# - Team collaboration features
# - Automated planning and applies
# - Policy enforcement
# - Cost estimation
#
# To use either backend, uncomment the relevant section and
# configure the required resources (S3 bucket, DynamoDB table,
# or Terraform Cloud workspace).

# ========================================
# Provider Authentication
# ========================================
# AWS Provider supports multiple authentication methods:
#
# 1. Environment Variables:
#    - AWS_ACCESS_KEY_ID
#    - AWS_SECRET_ACCESS_KEY
#    - AWS_SESSION_TOKEN (for temporary credentials)
#    - AWS_REGION
#
# 2. AWS CLI Configuration:
#    - ~/.aws/credentials
#    - ~/.aws/config
#    - AWS CLI profiles
#
# 3. IAM Roles:
#    - EC2 instance profiles
#    - ECS task roles
#    - Lambda execution roles
#
# 4. Assume Role:
#    - Cross-account access
#    - Role-based permissions
#
# 5. AWS SSO:
#    - Single sign-on integration
#    - Temporary credentials

# ========================================
# Security Considerations
# ========================================
# 1. Never commit AWS credentials to version control
# 2. Use IAM roles instead of access keys when possible
# 3. Enable MFA for AWS accounts
# 4. Regularly rotate access keys
# 5. Use least privilege principle for IAM permissions
# 6. Enable CloudTrail for API logging
# 7. Use AWS Config for compliance monitoring
# 8. Consider using AWS Secrets Manager for sensitive data