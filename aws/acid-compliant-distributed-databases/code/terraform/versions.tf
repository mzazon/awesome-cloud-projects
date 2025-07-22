# ============================================================================
# Terraform and Provider Version Requirements
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # AWS Provider for main infrastructure resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Random provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  
  # Example backend configuration (uncomment and modify for your use case)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "qldb/financial-ledger/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# ============================================================================
# AWS Provider Configuration
# ============================================================================

provider "aws" {
  # AWS region will be determined by:
  # 1. AWS_REGION environment variable
  # 2. AWS CLI configuration
  # 3. Instance metadata (if running on EC2)
  
  # Shared configuration and credentials
  # Uses default profile unless AWS_PROFILE is set
  
  # Default tags applied to all resources created by this provider
  default_tags {
    tags = {
      ManagedBy          = "terraform"
      Project           = "qldb-financial-ledger"
      TerraformModule   = "building-acid-compliant-distributed-databases-amazon-qldb"
      ComplianceLevel   = "financial-services"
      DataClassification = "highly-confidential"
    }
  }
}

# ============================================================================
# Random Provider Configuration
# ============================================================================

provider "random" {
  # Random provider configuration
  # Used for generating unique suffixes for resource names
}