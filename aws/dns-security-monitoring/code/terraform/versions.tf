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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "dns-security-monitoring"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "implementing-automated-dns-security-monitoring-with-route-53-resolver-dns-firewall-and-cloudwatch"
    }
  }
}