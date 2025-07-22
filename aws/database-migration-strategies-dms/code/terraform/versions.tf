# AWS Database Migration Service (DMS) Provider Requirements
# This file specifies the required Terraform and provider versions

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.4"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}