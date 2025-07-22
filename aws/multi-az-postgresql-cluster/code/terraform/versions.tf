# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and providers

terraform {
  required_version = ">= 1.0"

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

  # Backend configuration - uncomment and configure for remote state
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "postgresql-ha/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PostgreSQL-HA-Cluster"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "high-availability-postgresql-clusters-amazon-rds"
    }
  }
}

# Configure the AWS Provider for DR region
provider "aws" {
  alias  = "dr_region"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "PostgreSQL-HA-Cluster"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "high-availability-postgresql-clusters-amazon-rds"
    }
  }
}

# Random provider for generating unique identifiers
provider "random" {}