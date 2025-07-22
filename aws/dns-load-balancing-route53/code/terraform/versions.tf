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

# Configure the AWS Provider
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "dns-load-balancing"
      Recipe      = "route53-multi-region-lb"
      ManagedBy   = "terraform"
    }
  }
}

# Provider configuration for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "dns-load-balancing"
      Recipe      = "route53-multi-region-lb"
      ManagedBy   = "terraform"
    }
  }
}

# Provider configuration for tertiary region
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "dns-load-balancing"
      Recipe      = "route53-multi-region-lb"
      ManagedBy   = "terraform"
    }
  }
}