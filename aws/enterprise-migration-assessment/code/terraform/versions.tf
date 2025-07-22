# versions.tf - Provider requirements and version constraints
# This file defines the required providers and their version constraints
# for the Enterprise Migration Assessment infrastructure

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
    
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Configure the Random Provider for generating unique resource names
provider "random" {}

# Configure the Time Provider for resource scheduling
provider "time" {}