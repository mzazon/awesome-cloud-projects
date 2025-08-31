# Provider requirements and Terraform version constraints
# This file specifies the required providers and their versions

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
      version = "~> 3.5"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AgentCore Performance Monitoring"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Recipe      = "performance-monitoring-agentcore-cloudwatch"
    }
  }
}