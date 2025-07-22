# versions.tf - Provider requirements and version constraints

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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "IoT Data Ingestion Pipeline"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "iot-data-ingestion-aws-iot-core"
    }
  }
}