# Terraform and provider version requirements
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
  default_tags {
    tags = {
      Project     = "VPC-Lattice-TLS-Passthrough"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}