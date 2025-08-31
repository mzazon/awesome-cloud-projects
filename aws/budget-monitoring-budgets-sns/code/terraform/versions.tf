# Terraform and AWS provider version requirements
# This configuration specifies the minimum versions required for reliable operation

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Optional: Configure default tags for all resources
  default_tags {
    tags = {
      Project     = "budget-monitoring"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "budget-monitoring-budgets-sns"
    }
  }
}