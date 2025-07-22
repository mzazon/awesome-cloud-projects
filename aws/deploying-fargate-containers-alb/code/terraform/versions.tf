terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Fargate-Serverless-Containers"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "serverless-containers-fargate-application-load-balancer"
    }
  }
}

provider "random" {}