# Terraform provider requirements for Oracle to PostgreSQL migration with AWS DMS
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "OracleToPostgreSQLMigration"
      Environment = var.environment
      Owner       = var.owner
      CreatedBy   = "Terraform"
    }
  }
}