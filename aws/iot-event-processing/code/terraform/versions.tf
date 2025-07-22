# versions.tf - Provider and Terraform version requirements

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
  # Configuration will be taken from environment variables or AWS CLI configuration
  # AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, or AWS_PROFILE
  
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "IoTRulesEngine"
      Repository  = "recipes/aws/iot-rules-engine-event-processing"
      CreatedBy   = "terraform"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No configuration needed
}

# Configure the Archive Provider  
provider "archive" {
  # No configuration needed
}