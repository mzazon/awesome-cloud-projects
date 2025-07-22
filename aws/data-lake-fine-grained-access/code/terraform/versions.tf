# Terraform version and provider requirements
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

  # Common tags to apply to all resources
  default_tags {
    tags = {
      Project     = "DataLakeFormationFGAC"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "data-lake-formation-fine-grained-access-control"
    }
  }
}

# Configure random provider for unique naming
provider "random" {}