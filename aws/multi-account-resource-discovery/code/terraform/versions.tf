# Automated Multi-Account Resource Discovery - Terraform Provider Configuration
# This file specifies the required Terraform version and provider versions for the solution

terraform {
  # Specify the minimum required Terraform version
  required_version = ">= 1.5"

  # Define required providers with version constraints
  required_providers {
    # AWS Provider - Primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider - Used for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider - Used for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider with default settings
provider "aws" {
  # Provider settings will be inherited from environment variables:
  # - AWS_REGION or AWS_DEFAULT_REGION
  # - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  # - AWS_PROFILE (if using named profiles)
  # - Or from IAM roles when running in AWS environments

  # Default tags applied to all resources managed by this provider
  default_tags {
    tags = {
      # Terraform management tags
      ManagedBy           = "Terraform"
      TerraformWorkspace  = terraform.workspace
      TerraformProject    = "automated-multi-account-resource-discovery"
      
      # Solution identification tags
      Solution            = "AWS Multi-Account Resource Discovery"
      Component           = "Infrastructure"
      
      # Operational tags
      BackupRequired      = "false"
      MonitoringEnabled   = "true"
      ComplianceScope     = "Organization"
      
      # Cost management tags
      CostCenter          = "IT-Operations"
      Owner               = "Cloud-Engineering"
      
      # Lifecycle tags
      CreatedBy           = "Terraform"
      LastUpdated         = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required for random provider
}

# Configure the Archive Provider  
provider "archive" {
  # No specific configuration required for archive provider
}

# Version constraints explanation:
#
# AWS Provider (~> 5.0):
# - Uses the "pessimistic constraint operator" (~>)
# - Allows 5.x.x versions but not 6.0.0 or higher
# - Provides access to the latest AWS services and features
# - Includes support for Resource Explorer and enhanced Config features
#
# Random Provider (~> 3.1):
# - Supports the random_id resource used for unique naming
# - Stable provider with consistent API
#
# Archive Provider (~> 2.2):
# - Required for creating Lambda deployment ZIP files
# - Supports the data.archive_file data source
#
# Terraform Version (>= 1.5):
# - Required for advanced features like import blocks
# - Provides enhanced error messages and validation
# - Supports the latest HCL language features used in this configuration

# Important Notes:
#
# 1. Provider Authentication:
#    - Ensure AWS credentials are properly configured
#    - For Organizations features, must be run from management account
#    - Or configure appropriate cross-account roles
#
# 2. AWS Permissions Required:
#    - Organizations: Full access (for trusted access enablement)
#    - Config: Full access (for aggregators and rules)
#    - Resource Explorer: Full access (for indexes and views)  
#    - Lambda: Full access (for function deployment)
#    - EventBridge: Full access (for automation rules)
#    - S3: Full access (for Config bucket)
#    - IAM: Role and policy management permissions
#    - CloudWatch: Logs and dashboard creation permissions
#
# 3. Multi-Account Considerations:
#    - This configuration should be deployed from the Organizations management account
#    - Trusted access must be enabled for Config and Resource Explorer
#    - Member accounts may need additional configuration for full functionality
#
# 4. State Management:
#    - Consider using remote state (S3 + DynamoDB) for team environments
#    - Enable state encryption for sensitive data protection
#    - Implement proper state locking to prevent concurrent modifications
#
# 5. Version Pinning:
#    - The version constraints allow for minor updates while preventing breaking changes
#    - For production deployments, consider pinning to specific versions
#    - Test provider updates in non-production environments first