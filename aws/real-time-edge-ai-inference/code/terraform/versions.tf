# Terraform version and provider requirements
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "EdgeAIInference"
      Environment = var.environment
      Recipe      = "implementing-real-time-edge-ai-inference-with-sagemaker-edge-manager-and-iot-greengrass"
      ManagedBy   = "Terraform"
    }
  }
}

provider "random" {}
provider "time" {}