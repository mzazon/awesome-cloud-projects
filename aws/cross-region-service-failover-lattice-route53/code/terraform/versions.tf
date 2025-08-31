# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure AWS Provider for Primary Region
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = merge(var.default_tags, {
      Environment = var.environment
      Region      = "primary"
      Recipe      = "cross-region-service-failover-lattice-route53"
    })
  }
}

# Configure AWS Provider for Secondary Region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = merge(var.default_tags, {
      Environment = var.environment
      Region      = "secondary"
      Recipe      = "cross-region-service-failover-lattice-route53"
    })
  }
}

# Default provider for Route53 (global service)
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = merge(var.default_tags, {
      Environment = var.environment
      Recipe      = "cross-region-service-failover-lattice-route53"
    })
  }
}