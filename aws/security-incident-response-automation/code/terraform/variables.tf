# Variables for automated security incident response with AWS Security Hub
#
# This file defines all configurable variables for the incident response infrastructure
# including resource naming, notification settings, and operational parameters.

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "security-incident-response"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Owner or team responsible for this infrastructure"
  type        = string
  default     = "security-team"
}

# Security Hub Configuration
variable "enable_security_hub_standards" {
  description = "Enable default security standards in Security Hub"
  type        = bool
  default     = true
}

variable "security_standards" {
  description = "List of security standards to enable in Security Hub"
  type        = list(string)
  default = [
    "standards/aws-foundational-security-standard/v/1.0.0",
    "standards/cis-aws-foundations-benchmark/v/1.2.0"
  ]
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for security incident notifications"
  type        = string
  default     = "security-team@company.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_email_notifications" {
  description = "Enable email notifications for security incidents"
  type        = bool
  default     = true
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications for security incidents"
  type        = bool
  default     = false
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Event Processing Configuration
variable "process_critical_findings" {
  description = "Enable processing of critical severity findings"
  type        = bool
  default     = true
}

variable "process_high_findings" {
  description = "Enable processing of high severity findings"
  type        = bool
  default     = true
}

variable "process_medium_findings" {
  description = "Enable processing of medium severity findings"
  type        = bool
  default     = true
}

variable "process_low_findings" {
  description = "Enable processing of low severity findings"
  type        = bool
  default     = false
}

variable "auto_remediation_enabled" {
  description = "Enable automatic remediation of security findings"
  type        = bool
  default     = true
}

variable "auto_remediation_severity_threshold" {
  description = "Minimum severity level for automatic remediation (CRITICAL, HIGH, MEDIUM, LOW)"
  type        = string
  default     = "HIGH"
  
  validation {
    condition = contains(["CRITICAL", "HIGH", "MEDIUM", "LOW"], var.auto_remediation_severity_threshold)
    error_message = "Auto remediation severity threshold must be one of: CRITICAL, HIGH, MEDIUM, LOW."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

# Resource Naming
variable "resource_name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = ""
}

variable "resource_name_suffix" {
  description = "Suffix for resource names (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# Security Configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for supported resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Cost Management
variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for resources"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "security"
}