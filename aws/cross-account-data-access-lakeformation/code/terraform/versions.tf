# Terraform and provider version requirements for Lake Formation cross-account data access
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

# Configure the AWS Provider for the producer account
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = "cross-account-lake-formation"
      ManagedBy     = "terraform"
      Recipe        = "cross-account-data-access-lake-formation"
      LastUpdated   = timestamp()
    }
  }
}

# Configure the AWS Provider for consumer account operations
provider "aws" {
  alias  = "consumer"
  region = var.aws_region

  # Consumer account configuration
  assume_role {
    role_arn = var.consumer_account_assume_role_arn
  }

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = "cross-account-lake-formation-consumer"
      ManagedBy     = "terraform"
      Recipe        = "cross-account-data-access-lake-formation"
      LastUpdated   = timestamp()
    }
  }
}