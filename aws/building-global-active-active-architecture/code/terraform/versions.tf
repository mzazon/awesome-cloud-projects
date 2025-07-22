# Terraform version and provider requirements for multi-region Global Accelerator deployment
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Primary region provider (US East 1)
provider "aws" {
  alias  = "us_east"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-active-active-global-accelerator"
    }
  }
}

# Secondary region provider (EU West 1)
provider "aws" {
  alias  = "eu_west"
  region = var.secondary_region_eu
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-active-active-global-accelerator"
    }
  }
}

# Secondary region provider (Asia Pacific Southeast 1)
provider "aws" {
  alias  = "asia_southeast"
  region = var.secondary_region_asia
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-active-active-global-accelerator"
    }
  }
}

# Global Accelerator requires us-west-2 region
provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "multi-region-active-active-global-accelerator"
    }
  }
}