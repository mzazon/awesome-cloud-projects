# Terraform version requirements and provider configurations
# This file defines the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

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

# Primary AWS provider configuration (us-east-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Application = "ECommerce"
      Environment = var.environment
      Recipe      = "advanced-dynamodb-streaming-global-tables"
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary AWS provider configuration (eu-west-1)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Application = "ECommerce"
      Environment = var.environment
      Recipe      = "advanced-dynamodb-streaming-global-tables"
      ManagedBy   = "Terraform"
    }
  }
}

# Tertiary AWS provider configuration (ap-southeast-1)
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region

  default_tags {
    tags = {
      Application = "ECommerce"
      Environment = var.environment
      Recipe      = "advanced-dynamodb-streaming-global-tables"
      ManagedBy   = "Terraform"
    }
  }
}