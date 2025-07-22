# versions.tf - Terraform and Provider Version Constraints
# 
# This file defines the required Terraform version and provider version constraints
# for the high-performance file systems recipe using Amazon FSx.
#
# Version Strategy:
# - Use pessimistic version constraints (~>) to allow minor updates while preventing breaking changes
# - Terraform >= 1.5.0 for enhanced provider configuration and state management features
# - AWS Provider ~> 5.0 for full FSx service feature support and improved resource lifecycle management
# - Random Provider ~> 3.6 for unique resource naming with improved entropy generation

terraform {
  # Require Terraform 1.5.0 or later for:
  # - Enhanced provider configuration with validation
  # - Improved state management and locking
  # - Better error handling and resource planning
  # - Support for optional object type attributes
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider version ~> 5.0 provides:
    # - Full Amazon FSx service support including Lustre, Windows File Server, and NetApp ONTAP
    # - Enhanced security group and VPC management
    # - Improved CloudWatch integration and monitoring capabilities
    # - Support for latest FSx features like data compression and auto-import policies
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider version ~> 3.6 provides:
    # - Improved entropy generation for unique resource naming
    # - Enhanced string generation with better character sets
    # - Stable resource recreation behavior
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Configure remote state backend for production deployments
  # Uncomment and configure the following block for team environments:
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "recipes/fsx/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# Configure AWS Provider with default tags for resource governance
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources created by this configuration
  # These tags support cost allocation, governance, and lifecycle management
  default_tags {
    tags = {
      # Infrastructure metadata
      Environment     = var.environment
      Project         = "recipes"
      Recipe          = "high-performance-file-systems-amazon-fsx"
      ManagedBy      = "terraform"
      
      # Cost management and chargeback
      CostCenter     = var.cost_center
      Owner          = var.owner
      
      # Governance and compliance
      CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
      TerraformPath  = path.module
    }
  }
}

# Configure Random Provider for unique resource naming
provider "random" {
  # No specific configuration required
  # The provider will use secure random generation for resource names
}