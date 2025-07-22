# Variables for multi-account governance infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid AWS region format."
  }
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "organization_name_prefix" {
  description = "Prefix for organization-related resource names"
  type        = string
  default     = "enterprise-org"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.organization_name_prefix))
    error_message = "Organization name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_all_features" {
  description = "Enable all features in AWS Organizations (required for SCPs)"
  type        = bool
  default     = true
}

variable "create_member_accounts" {
  description = "Whether to create example member accounts"
  type        = bool
  default     = false
}

variable "member_accounts" {
  description = "List of member accounts to create"
  type = list(object({
    name  = string
    email = string
    ou    = string
  }))
  default = [
    {
      name  = "Production Account 1"
      email = "aws-prod1@example.com"
      ou    = "Production"
    },
    {
      name  = "Development Account 1"
      email = "aws-dev1@example.com"
      ou    = "Development"
    },
    {
      name  = "Sandbox Account 1"
      email = "aws-sandbox1@example.com"
      ou    = "Sandbox"
    }
  ]
}

variable "cloudtrail_retention_days" {
  description = "Number of days to retain CloudTrail logs"
  type        = number
  default     = 90
  
  validation {
    condition = var.cloudtrail_retention_days >= 1 && var.cloudtrail_retention_days <= 365
    error_message = "CloudTrail retention days must be between 1 and 365."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 5000
  
  validation {
    condition = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_notification_emails" {
  description = "List of email addresses for budget notifications"
  type        = list(string)
  default     = ["admin@example.com"]
  
  validation {
    condition = length(var.budget_notification_emails) > 0
    error_message = "At least one notification email must be provided."
  }
}

variable "allowed_regions" {
  description = "List of allowed AWS regions for region restriction policy"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
  
  validation {
    condition = length(var.allowed_regions) > 0
    error_message = "At least one allowed region must be specified."
  }
}

variable "max_instance_types" {
  description = "List of maximum instance types to deny"
  type        = list(string)
  default = [
    "*.8xlarge",
    "*.12xlarge", 
    "*.16xlarge",
    "*.24xlarge",
    "p3.*",
    "p4.*",
    "x1e.*"
  ]
}

variable "required_tags" {
  description = "List of required tags for cost allocation"
  type        = list(string)
  default     = ["Department", "Project", "Environment", "Owner"]
}

variable "enable_cloudtrail" {
  description = "Enable organization-wide CloudTrail"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config organization-wide"
  type        = bool
  default     = false
}

variable "enable_cost_anomaly_detection" {
  description = "Enable cost anomaly detection"
  type        = bool
  default     = true
}