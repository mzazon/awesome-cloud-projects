# Terraform and Provider Version Requirements
# This file defines the minimum required versions for Terraform and AWS provider
# to ensure compatibility with Aurora Global Database features

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

# Primary AWS Provider (US East 1)
# This provider handles the primary Aurora cluster and global database creation
provider "aws" {
  alias  = "primary"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "aurora-global-database"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Secondary AWS Provider (Europe West 1)
# This provider manages the European Aurora cluster with write forwarding
provider "aws" {
  alias  = "secondary_eu"
  region = var.secondary_region_eu
  
  default_tags {
    tags = {
      Project     = "aurora-global-database"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Secondary AWS Provider (Asia Pacific Southeast 1)
# This provider manages the Asian Aurora cluster with write forwarding
provider "aws" {
  alias  = "secondary_asia"
  region = var.secondary_region_asia
  
  default_tags {
    tags = {
      Project     = "aurora-global-database"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}