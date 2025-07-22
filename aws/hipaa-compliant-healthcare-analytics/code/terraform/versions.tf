# Terraform and Provider Version Requirements
# This file specifies the minimum versions required for Terraform and AWS provider

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

    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }

    # Template provider for processing Lambda function code
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Optional: Terraform Cloud/Enterprise configuration
  # Uncomment and configure if using Terraform Cloud or Enterprise
  # cloud {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "healthcare-data-processing"
  #   }
  # }

  # Optional: S3 backend configuration for state storage
  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "healthcare/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedBy          = "terraform"
      Recipe             = "healthcare-data-processing-pipelines-healthlake"
      TerraformVersion   = "~> 1.0"
      AWSProviderVersion = "~> 5.0"
      CostCenter         = var.cost_center
      ComplianceLevel    = var.compliance_level
      DataClassification = var.data_classification
    }
  }

  # Ignore tags applied outside of Terraform (e.g., by AWS services)
  ignore_tags {
    key_prefixes = ["aws:", "kubernetes.io/", "k8s.io/"]
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration required
}

# Configure the Template Provider
provider "template" {
  # No specific configuration required
}