# Terraform and provider version requirements for automated report generation infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider for creating Lambda deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = merge(
      {
        Project             = var.project_name
        Environment         = var.environment
        ManagedBy          = "Terraform"
        CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
        Recipe             = "automated-report-generation-eventbridge-scheduler-s3"
        TerraformModule    = "automated-reports"
        CostCenter         = "Infrastructure"
        Owner              = "DevOps"
        Backup             = "Required"
        Monitoring         = "CloudWatch"
        Compliance         = "SOC2"
      },
      var.additional_tags
    )
  }
}

# Random Provider configuration
provider "random" {}

# Archive Provider configuration  
provider "archive" {}