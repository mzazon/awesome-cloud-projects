# Terraform version and provider requirements for AWS Multi-Region Backup Strategy
# This configuration uses the latest stable AWS provider with features for
# comprehensive backup management across multiple regions

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Primary region provider for main backup operations
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "Multi-Region Backup Strategy"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary region provider for backup replication
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = "Multi-Region Backup Strategy"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Tertiary region provider for long-term archival
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region

  default_tags {
    tags = {
      Project     = "Multi-Region Backup Strategy"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}