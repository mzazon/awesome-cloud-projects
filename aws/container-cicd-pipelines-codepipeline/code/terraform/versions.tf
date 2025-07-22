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
      Project           = var.project_name
      Environment       = var.environment
      ManagedBy        = "Terraform"
      Recipe           = "cicd-pipelines-container-applications"
      CostCenter       = var.cost_center
      Owner            = var.owner
    }
  }
}