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
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS Provider for the Security Hub administrator account
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CrossAccountCompliance"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "implementing-cross-account-compliance-monitoring"
    }
  }
}

# Configure additional provider for member account 1
provider "aws" {
  alias  = "member1"
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${var.member_account_1}:role/OrganizationAccountAccessRole"
  }
  
  default_tags {
    tags = {
      Project     = "CrossAccountCompliance"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "implementing-cross-account-compliance-monitoring"
    }
  }
}

# Configure additional provider for member account 2
provider "aws" {
  alias  = "member2"
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${var.member_account_2}:role/OrganizationAccountAccessRole"
  }
  
  default_tags {
    tags = {
      Project     = "CrossAccountCompliance"
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "implementing-cross-account-compliance-monitoring"
    }
  }
}