# Terraform and Provider Version Requirements
# This file specifies the minimum required versions for Terraform and providers
# to ensure compatibility and access to required features

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider - primary provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }

    # Random Provider - used for generating unique resource suffixes
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0, < 4.0.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  # Default tags applied to all resources created by this provider
  default_tags {
    tags = merge(
      {
        # Infrastructure metadata tags
        "TerraformManaged" = "true"
        "Project"         = "CloudFormation Guard Policy Validation"
        "Component"       = "Policy as Code Infrastructure"
        "Repository"      = "recipes/aws/infrastructure-policy-validation-cloudformation-guard"
        
        # Compliance and governance tags
        "ComplianceFramework" = "AWS Well-Architected"
        "SecurityReviewed"    = "true"
        "DataClassification"  = "Internal"
        
        # Operational tags
        "BackupRequired"      = "false"
        "MaintenanceWindow"   = "Weekend"
        "MonitoringEnabled"   = "true"
        
        # Cost management tags
        "CostOptimized"       = "true"
        "LifecycleManaged"    = "true"
      },
      var.additional_tags
    )
  }

  # Enable retries for API throttling and transient errors
  retry_mode = "adaptive"
  max_retries = 3

  # Use IMDSv2 for enhanced security when running on EC2
  ec2_metadata_service_endpoint_mode = "IPv4"
  ec2_metadata_service_endpoint = "http://169.254.169.254"
}

# Random Provider Configuration
provider "random" {
  # No specific configuration required for random provider
}