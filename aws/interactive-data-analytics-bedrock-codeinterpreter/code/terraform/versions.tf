# Terraform and AWS Provider version requirements for Interactive Data Analytics with Bedrock AgentCore
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.46"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = {
      Project     = "interactive-data-analytics"
      Environment = var.environment
      Recipe      = "bedrock-agentcore-code-interpreter"
      ManagedBy   = "terraform"
    }
  }
}