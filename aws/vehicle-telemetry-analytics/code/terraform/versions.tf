# Terraform configuration with required providers
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FleetWise Telemetry Analytics"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "implementing-real-time-vehicle-telemetry-analytics-with-aws-iot-fleetwise-and-timestream"
    }
  }
}

# Random provider for generating unique suffixes
provider "random" {}