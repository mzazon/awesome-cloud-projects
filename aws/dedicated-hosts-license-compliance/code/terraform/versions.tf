# Terraform and provider version requirements
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
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment       = var.environment
      Project          = "dedicated-hosts-license-compliance"
      ManagedBy        = "terraform"
      Purpose          = "BYOL-License-Compliance"
      Recipe           = "aws-dedicated-hosts-license-compliance"
      CreatedDate      = formatdate("YYYY-MM-DD", timestamp())
    }
  }
}