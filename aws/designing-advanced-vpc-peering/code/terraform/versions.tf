# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider

terraform {
  required_version = ">= 1.5"
  
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

# Configure AWS Provider for Primary Region (US-East-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-vpc-peering-complex-routing"
    }
  }
}

# Configure AWS Provider for Secondary Region (US-West-2)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-vpc-peering-complex-routing"
    }
  }
}

# Configure AWS Provider for EU Region (EU-West-1)
provider "aws" {
  alias  = "eu"
  region = var.eu_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-vpc-peering-complex-routing"
    }
  }
}

# Configure AWS Provider for APAC Region (AP-Southeast-1)
provider "aws" {
  alias  = "apac"
  region = var.apac_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-vpc-peering-complex-routing"
    }
  }
}