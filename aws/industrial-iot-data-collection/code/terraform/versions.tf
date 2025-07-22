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
  default_tags {
    tags = {
      Project     = "industrial-iot-sitewise"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}