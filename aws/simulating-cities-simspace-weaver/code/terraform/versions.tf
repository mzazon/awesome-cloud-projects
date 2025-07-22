# Terraform version constraints and provider requirements
# Smart City Digital Twins with SimSpace Weaver and IoT

terraform {
  # Require Terraform version 1.0 or newer for stability and feature support
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - Official HashiCorp AWS provider
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.4"
    }

    # Archive Provider - For creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random Provider - For generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Template Provider - For processing template files (if needed for complex configurations)
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }

    # Null Provider - For local-exec and external integrations
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Default AWS provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      ManagedBy                = "Terraform"
      Project                  = "Smart City Digital Twins"
      Solution                 = "IoT-SimSpace-Weaver-Analytics"
      TerraformConfiguration   = "smart-city-digital-twins-simspace-weaver-iot"
      LastModified            = timestamp()
      Environment             = var.environment
    }
  }
}

# Archive provider (no additional configuration needed)
provider "archive" {}

# Random provider (no additional configuration needed) 
provider "random" {}

# Template provider (no additional configuration needed)
provider "template" {}

# Null provider (no additional configuration needed)
provider "null" {}

# AWS provider version data for documentation
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for provider information
locals {
  provider_info = {
    terraform_version = ">= 1.0"
    aws_provider     = "~> 6.4"
    archive_provider = "~> 2.4"
    random_provider  = "~> 3.6"
    template_provider = "~> 2.2"
    null_provider    = "~> 3.2"
  }
}

# Output provider version information for reference
output "provider_versions" {
  description = "Provider version constraints used in this configuration"
  value       = local.provider_info
}

# Terraform configuration constraints and best practices
locals {
  terraform_requirements = {
    minimum_version = "1.0.0"
    recommended_version = ">= 1.6.0"
    features_used = [
      "provider_default_tags",
      "sensitive_outputs",
      "validation_blocks",
      "dynamic_blocks",
      "for_each_expressions",
      "conditional_expressions"
    ]
    backend_options = [
      "s3_with_dynamodb_locking",
      "terraform_cloud", 
      "local_development_only"
    ]
  }
}

# Optional: Terraform backend configuration (commented out - configure as needed)
# Note: Uncomment and configure for production deployments
/*
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "smart-city/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
    
    # Optional: Configure additional backend settings
    # versioning     = true
    # force_path_style = false
  }
}
*/

# Alternative backend configurations:

# Terraform Cloud backend
/*
terraform {
  cloud {
    organization = "your-organization"
    workspaces {
      name = "smart-city-digital-twins"
    }
  }
}
*/

# Azure backend (if using Azure for state management)
/*
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstateaccount"
    container_name       = "tfstate"
    key                  = "smart-city.terraform.tfstate"
  }
}
*/

# Google Cloud Storage backend (if using GCS for state management)
/*
terraform {
  backend "gcs" {
    bucket  = "your-terraform-state-bucket"
    prefix  = "smart-city"
  }
}
*/

# Version compatibility matrix and recommendations
locals {
  compatibility_matrix = {
    terraform_1_0 = {
      aws_provider = "~> 4.0"
      status       = "minimum_supported"
    }
    terraform_1_3 = {
      aws_provider = "~> 5.0" 
      status       = "recommended_minimum"
    }
    terraform_1_6 = {
      aws_provider = "~> 6.0"
      status       = "current_recommended"
    }
  }

  # AWS provider feature requirements
  aws_features_required = [
    "iot_topic_rule_error_action",
    "lambda_event_source_mapping_filter_criteria", 
    "dynamodb_point_in_time_recovery",
    "s3_bucket_separate_configuration_resources",
    "iam_policy_document_data_source"
  ]
}

# Development vs Production provider settings
locals {
  provider_settings = {
    development = {
      skip_credentials_validation = false
      skip_region_validation     = false
      skip_requesting_account_id = false
      max_retries               = 3
    }
    production = {
      skip_credentials_validation = false
      skip_region_validation     = false  
      skip_requesting_account_id = false
      max_retries               = 5
      # Additional production settings
      assume_role = {
        # Configure cross-account access if needed
        # role_arn = "arn:aws:iam::ACCOUNT:role/TerraformExecutionRole"
        # session_name = "TerraformSession"
      }
    }
  }
}

# Provider feature flags and experimental features
# Note: These are informational and may not all be available
locals {
  provider_features = {
    aws = {
      # Features that may be toggled in newer provider versions
      s3_use_path_style                    = false
      dynamodb_ignore_tags_on_create       = false  
      lambda_reserved_concurrent_executions = true
      iot_ignore_tags_on_create            = false
    }
  }
}

# Terraform workspace configuration recommendations
locals {
  workspace_recommendations = {
    development = {
      auto_approve         = false
      destroy_protection   = false
      resource_limits     = "relaxed"
      cost_controls       = "monitoring_only"
    }
    staging = {
      auto_approve         = false  
      destroy_protection   = true
      resource_limits     = "moderate"
      cost_controls       = "alerts_and_budgets"
    }
    production = {
      auto_approve         = false
      destroy_protection   = true
      resource_limits     = "strict"
      cost_controls       = "full_governance"
      backup_required     = true
      monitoring_required = true
    }
  }
}