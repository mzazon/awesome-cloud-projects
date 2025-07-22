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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "real-time-recommendations-personalize-ab-testing"
    }
  }
}