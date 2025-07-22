# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"

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
  default_tags {
    tags = {
      Project     = "ConversationalAI"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "conversational-ai-applications-amazon-bedrock-claude"
    }
  }
}