# ====================================
# TERRAFORM VERSION REQUIREMENTS
# ====================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for primary and DR region resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and customize the backend configuration below based on your requirements
  
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "aws-backup-solution/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # backend "remote" {
  #   organization = "your-organization"
  #   workspaces {
  #     name = "aws-backup-solution"
  #   }
  # }
}