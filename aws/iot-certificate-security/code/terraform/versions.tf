# Terraform provider requirements for IoT Security implementation
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
      Project     = "IoT Security"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "iot-security-device-certificates-policies"
    }
  }
}