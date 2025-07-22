# Terraform configuration for ECR Container Registry Replication Strategies
# Defines provider requirements and version constraints

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Provider configuration for source region (us-east-1)
provider "aws" {
  region = var.source_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Provider configuration for destination region (us-west-2)
provider "aws" {
  alias  = "us_west_2"
  region = var.destination_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Provider configuration for secondary region (eu-west-1)
provider "aws" {
  alias  = "eu_west_1"
  region = var.secondary_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Random provider for generating unique suffixes
provider "random" {}