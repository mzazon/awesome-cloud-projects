# ================================================================
# Terraform and Provider Version Requirements
# Recipe: Persistent Customer Support Agent with Bedrock AgentCore Memory
# ================================================================

terraform {
  # Terraform version requirement
  required_version = ">= 1.6.0"

  # Required provider configurations
  required_providers {
    # AWS Provider for core AWS services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure according to your state management strategy
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "customer-support-agent/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ================================================================
# AWS PROVIDER CONFIGURATION
# ================================================================

provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project             = "CustomerSupportAgent"
      Recipe              = "persistent-customer-support-agentcore-memory"
      TerraformManaged    = "true"
      CreatedBy           = "Terraform"
      Environment         = var.tags.Environment
      # Add cost allocation tags if enabled
      CostCenter = var.enable_cost_allocation_tags ? var.cost_center : null
    }
  }

  # Optional: Assume role configuration for cross-account deployments
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  # }
}

# ================================================================
# RANDOM PROVIDER CONFIGURATION
# ================================================================

provider "random" {
  # No specific configuration required for random provider
}

# ================================================================
# ARCHIVE PROVIDER CONFIGURATION
# ================================================================

provider "archive" {
  # No specific configuration required for archive provider
}

# ================================================================
# PROVIDER FEATURE FLAGS AND EXPERIMENTAL FEATURES
# ================================================================

# Configure AWS provider features and experimental capabilities
# These settings help ensure consistent behavior across environments

# Note: Bedrock AgentCore is in preview - ensure your AWS account has access
# Contact AWS Support to enable Bedrock AgentCore if not already available

# ================================================================
# LOCAL VALUES FOR PROVIDER CONFIGURATION
# ================================================================

locals {
  # Common provider configuration values
  aws_region = var.aws_region
  
  # Validate region supports required services
  supported_regions = [
    "us-east-1",      # N. Virginia
    "us-west-2",      # Oregon
    "eu-west-1",      # Ireland
    "eu-central-1",   # Frankfurt
    "ap-southeast-1", # Singapore
    "ap-northeast-1"  # Tokyo
  ]
  
  # Check if region supports Bedrock AgentCore
  region_supported = contains(local.supported_regions, var.aws_region)
}

# ================================================================
# PROVIDER VERSION COMPATIBILITY NOTES
# ================================================================

# AWS Provider 5.31+ is required for:
# - Latest Bedrock AgentCore resources (preview features)
# - Enhanced API Gateway v2 support
# - Updated Lambda runtime support
# - Latest DynamoDB features and security settings
# - CloudWatch Logs retention policy updates

# Terraform 1.6.0+ is required for:
# - Enhanced provider configuration
# - Improved state management
# - Better error handling and validation
# - Support for complex variable validation rules

# Random Provider 3.6+ is required for:
# - Enhanced string generation options
# - Better entropy for resource naming
# - Improved deterministic behavior

# Archive Provider 2.4+ is required for:
# - Better file handling for Lambda packages
# - Enhanced compression options
# - Improved cross-platform compatibility

# ================================================================
# BACKWARD COMPATIBILITY NOTES
# ================================================================

# This configuration is designed to work with:
# - Terraform >= 1.6.0
# - AWS Provider >= 5.31.0
# - Modern AWS CLI versions (2.x)
# - Current AWS service APIs

# For older environments, consider:
# - Terraform 1.5.x with AWS Provider 5.20+
# - Adjust resource configurations as needed
# - Test thoroughly in non-production environments

# ================================================================
# SECURITY CONSIDERATIONS
# ================================================================

# Provider configuration security best practices:
# 1. Use IAM roles instead of access keys when possible
# 2. Enable CloudTrail logging for all API calls
# 3. Use encrypted state backends (S3 + DynamoDB)
# 4. Implement least privilege access policies
# 5. Regularly rotate access credentials
# 6. Use AWS Config for compliance monitoring

# ================================================================
# PERFORMANCE OPTIMIZATION
# ================================================================

# Provider performance considerations:
# 1. Use regional endpoints when possible
# 2. Configure appropriate timeouts for large deployments
# 3. Enable parallel operations where safe
# 4. Use data sources efficiently to avoid unnecessary API calls
# 5. Implement proper dependency management
# 6. Consider using provider aliases for multi-region deployments