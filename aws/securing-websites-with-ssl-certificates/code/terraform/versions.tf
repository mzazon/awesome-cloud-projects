# Terraform and Provider Version Requirements
# This file defines the minimum versions required for Terraform and AWS provider

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

  # Uncomment and configure for remote state storage
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "static-website/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Configure the AWS Provider
# Note: ACM certificates for CloudFront must be created in us-east-1
provider "aws" {
  region = var.aws_region
}

# Additional provider for us-east-1 (required for ACM certificates used with CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}