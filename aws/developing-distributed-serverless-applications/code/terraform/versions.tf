# Terraform provider requirements and version constraints
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for creating Aurora DSQL clusters and supporting resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for Lambda function deployments
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }

    # Null provider for executing local commands
    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}

# Primary AWS provider configuration for us-east-1
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Environment   = var.environment
      Application   = "multi-region-aurora-dsql"
      DeployedBy    = "terraform"
      Recipe        = "building-multi-region-applications-aurora-dsql"
      CostCenter    = var.cost_center
    }
  }
}

# Secondary AWS provider configuration for us-east-2
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Environment   = var.environment
      Application   = "multi-region-aurora-dsql"
      DeployedBy    = "terraform"
      Recipe        = "building-multi-region-applications-aurora-dsql"
      CostCenter    = var.cost_center
    }
  }
}

# Witness region AWS provider configuration for us-west-2
provider "aws" {
  alias  = "witness"
  region = var.witness_region

  default_tags {
    tags = {
      Environment   = var.environment
      Application   = "multi-region-aurora-dsql"
      DeployedBy    = "terraform"
      Recipe        = "building-multi-region-applications-aurora-dsql"
      CostCenter    = var.cost_center
    }
  }
}