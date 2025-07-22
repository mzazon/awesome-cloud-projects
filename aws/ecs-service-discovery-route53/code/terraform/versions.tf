# Terraform version and provider requirements for ECS Service Discovery with Route 53 and ALB
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

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ecs-service-discovery"
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "ecs-service-discovery-route53-application-load-balancer"
    }
  }
}