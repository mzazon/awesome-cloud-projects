# Terraform and provider version requirements for VPC Flow Logs monitoring
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "VPC-Flow-Logs-Monitoring"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "network-monitoring-vpc-flow-logs"
    }
  }
}