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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Analytics Workload Isolation"
      Recipe      = "analytics-workload-isolation-redshift-workload-management"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "random" {}