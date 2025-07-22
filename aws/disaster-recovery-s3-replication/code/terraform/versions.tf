# Terraform and provider version constraints
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
  }
}

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "S3-Disaster-Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "disaster-recovery-s3-cross-region-replication"
    }
  }
}

# Configure the AWS Provider for disaster recovery region
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  
  default_tags {
    tags = {
      Project     = "S3-Disaster-Recovery"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "disaster-recovery-s3-cross-region-replication"
    }
  }
}