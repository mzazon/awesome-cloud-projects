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
  }
}

# Default provider configuration
provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "global-load-balancing-route53-cloudfront"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for US East 1 (required for CloudFront and Route53)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "global-load-balancing-route53-cloudfront"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for primary region
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "global-load-balancing-route53-cloudfront"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "global-load-balancing-route53-cloudfront"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for tertiary region
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "global-load-balancing-route53-cloudfront"
      ManagedBy   = "terraform"
    }
  }
}