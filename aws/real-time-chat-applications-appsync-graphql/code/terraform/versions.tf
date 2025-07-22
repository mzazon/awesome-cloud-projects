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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "RealTimeChatApp"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "real-time-chat-applications-appsync-graphql"
    }
  }
}