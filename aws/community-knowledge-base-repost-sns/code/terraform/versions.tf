# Terraform version and provider requirements for Community Knowledge Base with re:Post Private and SNS
# This configuration deploys the SNS notification infrastructure for enterprise knowledge management

terraform {
  required_version = ">= 1.5.0"

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

  # Optional: Configure remote state backend
  # Uncomment and customize for production use
  # backend "s3" {
  #   bucket  = "your-terraform-state-bucket"
  #   key     = "community-knowledge-base/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  #   
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# Configure the AWS Provider with default tags
provider "aws" {
  default_tags {
    tags = {
      Project     = "Community Knowledge Base"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Service     = "re:Post Private with SNS"
      Recipe      = "community-knowledge-base-repost-sns"
    }
  }
}

# Provider for generating random values
provider "random" {}