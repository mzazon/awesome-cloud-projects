# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================

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

  # Optional: Configure remote state backend
  # Uncomment and modify the backend configuration below if you want to store
  # Terraform state in a remote backend like S3
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "s3-crr/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# =============================================================================
# Provider Configurations
# =============================================================================

# Default provider for source region
provider "aws" {
  region = var.source_region

  default_tags {
    tags = merge(var.tags, {
      Region      = var.source_region
      Component   = "source"
      Terraform   = "true"
      Repository  = "recipes"
    })
  }
}

# Provider alias for destination region
provider "aws" {
  alias  = "destination"
  region = var.destination_region

  default_tags {
    tags = merge(var.tags, {
      Region      = var.destination_region
      Component   = "destination"
      Terraform   = "true"
      Repository  = "recipes"
    })
  }
}

# Random provider for generating unique suffixes
provider "random" {
  # No configuration needed for random provider
}