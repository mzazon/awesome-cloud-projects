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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = "IdentityFederation"
      ManagedBy     = "Terraform"
      Recipe        = "identity-federation-aws-sso"
      CreatedDate   = timestamp()
    }
  }
}

# Configure the Random Provider
provider "random" {}

# Configure the Time Provider
provider "time" {}