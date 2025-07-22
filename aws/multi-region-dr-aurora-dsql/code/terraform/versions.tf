# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Primary region provider (us-east-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "DisasterRecovery"
      Environment = var.environment
      CostCenter  = "Infrastructure"
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary region provider (us-west-2)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = "DisasterRecovery"
      Environment = var.environment
      CostCenter  = "Infrastructure"
      ManagedBy   = "Terraform"
    }
  }
}

# Witness region provider (us-west-1)
provider "aws" {
  alias  = "witness"
  region = var.witness_region
  
  default_tags {
    tags = {
      Project     = "DisasterRecovery"
      Environment = var.environment
      CostCenter  = "Infrastructure"
      ManagedBy   = "Terraform"
    }
  }
}