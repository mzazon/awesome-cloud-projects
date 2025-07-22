# Terraform and provider version constraints
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project             = "SustainableArchive"
      Environment         = var.environment
      Purpose             = "SustainableArchive"
      CostOptimization    = "Enabled"
      SustainabilityGoal  = "CarbonNeutral"
      ManagedBy          = "Terraform"
    }
  }
}