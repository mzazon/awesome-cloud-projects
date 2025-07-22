# Terraform and Provider Version Requirements
# This configuration specifies the minimum required versions for Terraform and AWS provider

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
      version = "~> 2.4"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "cqrs-event-sourcing-eventbridge-dynamodb"
    }
  }
}