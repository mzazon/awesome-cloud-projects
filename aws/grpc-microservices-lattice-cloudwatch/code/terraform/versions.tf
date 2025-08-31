# Terraform and provider version requirements for gRPC microservices with VPC Lattice
terraform {
  required_version = ">= 1.5"

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
      Project     = "gRPC-Microservices"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "grpc-microservices-lattice-cloudwatch"
    }
  }
}