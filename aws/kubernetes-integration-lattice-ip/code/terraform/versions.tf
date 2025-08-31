# versions.tf - Provider requirements and version constraints

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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kubernetes-lattice-integration"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "kubernetes-integration-lattice-ip"
    }
  }
}