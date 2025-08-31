# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# with their version constraints for the traffic analytics solution

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for packaging Lambda functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }

    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }

    # Template provider for templating configurations
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Optional: Configure Terraform Cloud or backend for state management
  # Uncomment and configure as needed for your environment
  
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "traffic-analytics/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "traffic-analytics-vpc-lattice"
  #   }
  # }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy          = "terraform"
      Recipe             = "traffic-analytics-lattice-opensearch"
      TerraformWorkspace = terraform.workspace
      Owner              = var.owner != "" ? var.owner : "terraform"
      CostCenter         = var.cost_center != "" ? var.cost_center : "not-specified"
    }
  }
}

# Random Provider Configuration
provider "random" {
  # No specific configuration required
}

# Archive Provider Configuration  
provider "archive" {
  # No specific configuration required
}

# Local Provider Configuration
provider "local" {
  # No specific configuration required
}

# Template Provider Configuration
provider "template" {
  # No specific configuration required
}