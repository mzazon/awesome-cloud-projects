# Terraform configuration for Database Disaster Recovery with Read Replicas
# Provider version constraints and required providers

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Primary region provider configuration
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "DatabaseDisasterRecovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "database-disaster-recovery-cross-region-read-replicas"
    }
  }
}

# Disaster recovery region provider configuration
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  
  default_tags {
    tags = {
      Project     = "DatabaseDisasterRecovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "database-disaster-recovery-cross-region-read-replicas"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}