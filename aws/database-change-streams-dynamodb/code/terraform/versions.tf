# Terraform version and provider requirements for DynamoDB Streams solution

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
      version = "~> 3.6"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = {
      Project     = "DynamoDBStreams"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}