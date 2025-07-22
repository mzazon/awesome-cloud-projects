# Terraform and provider version requirements for AWS App2Container Infrastructure
# This configuration ensures compatibility with the latest features and security updates

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  # Optional: Configure remote state backend
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "app2container/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# AWS Provider configuration with default tags and settings
provider "aws" {
  # AWS region will be determined by AWS CLI configuration or environment variables
  # Override by setting TF_VAR_aws_region environment variable

  default_tags {
    tags = {
      Project     = "App2Container-Modernization"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "application-modernization-aws-app2container"
      Purpose     = "ApplicationModernization"
      CostCenter  = var.environment
      Repository  = "aws-app2container-terraform"
    }
  }

  # Enable assume role if needed for cross-account access
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT-ID:role/TerraformRole"
  # }
}

# Random provider configuration
provider "random" {
  # No configuration needed for random provider
}

# Local provider configuration
provider "local" {
  # No configuration needed for local provider
}