terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "RDS Disaster Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Configure the AWS Provider for secondary region (disaster recovery)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = "RDS Disaster Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}