# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and AWS provider

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Configure backend for remote state storage
  # Uncomment and configure for production deployments
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "multi-vpc-tgw/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.default_tags
  }
}

# Configure the AWS Provider for DR region
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = var.default_tags
  }
}