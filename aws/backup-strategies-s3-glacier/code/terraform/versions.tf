# versions.tf
# Terraform and provider version constraints for AWS backup strategies

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "backup-strategies-s3-glacier"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# Configure the AWS Provider for disaster recovery region
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "backup-strategies-s3-glacier"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Purpose     = "disaster-recovery"
    }
  }
}