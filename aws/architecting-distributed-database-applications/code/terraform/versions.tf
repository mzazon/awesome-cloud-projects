# versions.tf - Provider version constraints and required providers
# This file defines the minimum versions required for all Terraform providers

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

# Primary region provider (us-east-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = merge(var.common_tags, {
      Region = var.primary_region
      Role   = "Primary"
    })
  }
}

# Secondary region provider (us-west-2)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = merge(var.common_tags, {
      Region = var.secondary_region
      Role   = "Secondary"
    })
  }
}

# Random provider for generating unique identifiers
provider "random" {}

# Archive provider for Lambda function packaging
provider "archive" {}