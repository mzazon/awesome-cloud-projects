# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================

terraform {
  # Specify minimum Terraform version
  required_version = ">= 1.6.0"

  # Required providers with version constraints
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

  # Optional: Configure remote state backend
  # Uncomment and configure based on your needs
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "cloudwatch-monitoring/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# =============================================================================
# AWS Provider Configuration
# =============================================================================

provider "aws" {
  # Provider configuration will use environment variables or AWS profile
  # AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # Or AWS_PROFILE for named profiles
  
  # Optional: Specify default tags for all resources
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "CloudWatch-Monitoring"
      Environment = "Production"
      Repository  = "aws-cloudwatch-monitoring"
    }
  }
}

# =============================================================================
# Random Provider Configuration
# =============================================================================

provider "random" {
  # No specific configuration needed for random provider
}

# =============================================================================
# Data Sources for Current AWS Context
# =============================================================================

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get available AWS availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Common metadata
  common_tags = {
    Project        = "CloudWatch-Monitoring"
    Environment    = "Production"
    ManagedBy      = "Terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
    Repository     = "aws-cloudwatch-monitoring"
    Region         = data.aws_region.current.name
    AccountId      = data.aws_caller_identity.current.account_id
  }

  # Resource naming
  name_prefix = "monitoring"
  
  # Alarm configurations
  alarm_configs = {
    cpu = {
      metric_name = "CPUUtilization"
      namespace   = "AWS/EC2"
      statistic   = "Average"
    }
    response_time = {
      metric_name = "TargetResponseTime"
      namespace   = "AWS/ApplicationELB"
      statistic   = "Average"
    }
    db_connections = {
      metric_name = "DatabaseConnections"
      namespace   = "AWS/RDS"
      statistic   = "Average"
    }
  }
}

# =============================================================================
# Terraform Configuration Notes
# =============================================================================

# This configuration uses:
# - AWS Provider version 5.x for latest features and security updates
# - Random provider for generating unique resource names
# - Data sources for dynamic AWS account/region information
# - Local values for common configurations and computed values
# - Default tags applied to all resources via provider configuration
# - Flexible backend configuration (commented out by default)

# To use this configuration:
# 1. Ensure AWS credentials are configured (AWS CLI, environment variables, or IAM roles)
# 2. Run: terraform init
# 3. Run: terraform plan -var="notification_email=your-email@example.com"
# 4. Run: terraform apply -var="notification_email=your-email@example.com"

# For production use, consider:
# 1. Configuring a remote backend (S3 + DynamoDB)
# 2. Using terraform.tfvars file for variable values
# 3. Implementing state file encryption
# 4. Setting up proper IAM permissions for Terraform operations
# 5. Using separate configurations for different environments