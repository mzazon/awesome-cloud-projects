# Terraform provider version requirements for Advanced Request Routing with VPC Lattice and ALB
# This recipe requires Terraform 1.5+ and AWS Provider 6.0+

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider with enhanced features
provider "aws" {
  # Provider configuration can be set via environment variables:
  # AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  
  default_tags {
    tags = {
      Project     = "VPC-Lattice-Advanced-Routing"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "advanced-request-routing-lattice-alb"
    }
  }
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get availability zones in current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}