# Terraform and Provider Version Constraints
# DRM-Protected Video Streaming Infrastructure

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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DRM-Protected-Video-Streaming"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "video-content-protection-drm-mediapackage"
    }
  }
}