# Terraform and provider version requirements for Chat Notifications with SNS and Chatbot
# This file defines the minimum Terraform and provider versions required
# to deploy the chat notification infrastructure successfully.

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider - for creating AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Random Provider - for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# AWS Provider configuration with default tags applied to all resources
# This ensures consistent tagging across the entire infrastructure
provider "aws" {
  region = var.aws_region

  # Default tags applied to all AWS resources created by this configuration
  default_tags {
    tags = {
      Project     = "Chat Notifications with SNS and Chatbot"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "recipes/aws/chat-notifications-sns-chatbot"
    }
  }
}

# Random provider configuration for generating unique identifiers
provider "random" {}