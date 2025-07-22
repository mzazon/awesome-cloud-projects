# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and providers
# to ensure compatibility and access to required features

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"
  
  # Provider requirements with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    
    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
    
    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.2"
    }
  }
}

# AWS Provider Configuration
# Configure the AWS provider with optional default tags and region settings
provider "aws" {
  # Default tags applied to all resources managed by this provider
  default_tags {
    tags = {
      ManagedBy           = "Terraform"
      TerraformWorkspace  = terraform.workspace
      Recipe              = "intelligent-document-processing-amazon-textract"
      LastUpdated         = formatdate("YYYY-MM-DD", timestamp())
    }
  }
  
  # Additional provider configuration can be added here:
  # region = var.aws_region  # Uncomment if you want to specify region via variable
  # profile = var.aws_profile  # Uncomment if you want to specify profile via variable
  
  # Ignore tags for resources that may have tags added by other systems
  ignore_tags {
    keys = [
      "aws:cloudformation:stack-name",
      "aws:cloudformation:stack-id",
      "aws:cloudformation:logical-id"
    ]
  }
}

# Random Provider Configuration  
provider "random" {
  # No additional configuration required for random provider
}

# Archive Provider Configuration
provider "archive" {
  # No additional configuration required for archive provider
}