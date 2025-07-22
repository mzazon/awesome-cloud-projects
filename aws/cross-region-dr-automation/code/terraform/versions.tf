# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and providers
# to ensure compatibility and access to necessary features

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS Provider for primary region resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }
    
    # Archive provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

# Configure the AWS Provider for the primary region
provider "aws" {
  region = var.primary_region != "" ? var.primary_region : "us-east-1"
  
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "AWS-DRS-Automation"
      Environment = var.environment
    }
  }
}

# Configure the AWS Provider for the disaster recovery region
provider "aws" {
  alias  = "disaster_recovery"
  region = var.disaster_recovery_region != "" ? var.disaster_recovery_region : "us-west-2"
  
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "AWS-DRS-Automation"
      Environment = var.environment
      Purpose     = "DisasterRecovery"
    }
  }
}

# Additional provider configuration variables
variable "primary_region" {
  description = "Primary AWS region for DRS deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region identifier."
  }
}

variable "disaster_recovery_region" {
  description = "AWS region for disaster recovery deployment"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.disaster_recovery_region))
    error_message = "Disaster recovery region must be a valid AWS region identifier."
  }
}

# Provider features and configuration
provider "random" {
  # No specific configuration required
}

provider "archive" {
  # No specific configuration required
}