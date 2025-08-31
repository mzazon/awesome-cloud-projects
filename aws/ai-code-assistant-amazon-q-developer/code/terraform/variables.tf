# Amazon Q Developer Terraform Variables
# These variables configure the infrastructure for Amazon Q Developer

# Basic Configuration Variables

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "amazon-q-dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must be 3-32 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# IAM Role Configuration Variables

variable "create_admin_role" {
  description = "Whether to create an administrative IAM role for Amazon Q Developer management"
  type        = bool
  default     = true
}

variable "create_user_role" {
  description = "Whether to create a user IAM role for Amazon Q Developer access"
  type        = bool
  default     = false
}

variable "trusted_user_arns" {
  description = "List of IAM user or role ARNs that can assume the Amazon Q user role"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.trusted_user_arns : can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.*", arn))
    ])
    error_message = "All ARNs must be valid IAM user or role ARNs."
  }
}

# IAM Identity Center (SSO) Configuration Variables

variable "enable_identity_center" {
  description = "Whether to configure IAM Identity Center integration for Amazon Q Developer Pro"
  type        = bool
  default     = false
}

variable "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance for Amazon Q Developer Pro integration"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_identity_center == false || can(regex("^arn:aws:sso:::instance/ssoins-[a-f0-9]{16}$", var.identity_center_instance_arn))
    error_message = "Identity Center instance ARN must be in the format 'arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxxxxx' when Identity Center is enabled."
  }
}

variable "identity_center_user_ids" {
  description = "List of IAM Identity Center user IDs to grant Amazon Q Developer access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for user_id in var.identity_center_user_ids : can(regex("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", user_id))
    ])
    error_message = "All user IDs must be valid UUIDs."
  }
}

variable "session_duration" {
  description = "Maximum session duration for IAM Identity Center permission set (in ISO 8601 format)"
  type        = string
  default     = "PT8H"
  
  validation {
    condition = can(regex("^PT([0-9]{1,2}H|[0-9]{1,3}M)$", var.session_duration))
    error_message = "Session duration must be in ISO 8601 format (e.g., PT8H for 8 hours, PT480M for 480 minutes)."
  }
}

# Monitoring and Logging Configuration Variables

variable "enable_usage_monitoring" {
  description = "Whether to enable CloudWatch monitoring for Amazon Q Developer usage"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for Amazon Q Developer usage"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

# S3 Configuration Variables

variable "create_config_bucket" {
  description = "Whether to create an S3 bucket for storing Amazon Q Developer configuration and logs"
  type        = bool
  default     = false
}

variable "force_destroy_bucket" {
  description = "Whether to force destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

# Security and Compliance Variables

variable "enable_encryption" {
  description = "Whether to enable encryption for all supported resources"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP CIDR ranges allowed to access Amazon Q Developer resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Organization and Team Configuration Variables

variable "organization_name" {
  description = "Name of the organization using Amazon Q Developer"
  type        = string
  default     = ""
  
  validation {
    condition     = var.organization_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\s\\-_.]{1,62}[a-zA-Z0-9]$", var.organization_name))
    error_message = "Organization name must be 3-64 characters and contain only alphanumeric characters, spaces, hyphens, underscores, and periods."
  }
}

variable "team_tags" {
  description = "Additional tags to apply to resources for team or project identification"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.team_tags : can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\s\\-_.:/=+@]{0,254}[a-zA-Z0-9]$", k)) && can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\s\\-_.:/=+@]{0,254}[a-zA-Z0-9]$", v))
    ])
    error_message = "Tag keys and values must be 1-256 characters and follow AWS tag naming conventions."
  }
}

# Cost Management Variables

variable "enable_cost_alerts" {
  description = "Whether to enable cost alerts for Amazon Q Developer usage"
  type        = bool
  default     = false
}

variable "monthly_cost_threshold" {
  description = "Monthly cost threshold in USD for Amazon Q Developer usage alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_cost_threshold > 0 && var.monthly_cost_threshold <= 10000
    error_message = "Monthly cost threshold must be between 1 and 10,000 USD."
  }
}

variable "cost_alert_email" {
  description = "Email address to receive cost alerts for Amazon Q Developer usage"
  type        = string
  default     = ""
  
  validation {
    condition = var.cost_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.cost_alert_email))
    error_message = "Cost alert email must be a valid email address."
  }
}

# Advanced Configuration Variables

variable "custom_policy_statements" {
  description = "List of additional IAM policy statements to add to Amazon Q Developer roles"
  type = list(object({
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(map(any))
  }))
  default = []
  
  validation {
    condition = alltrue([
      for stmt in var.custom_policy_statements : contains(["Allow", "Deny"], stmt.effect)
    ])
    error_message = "All policy statement effects must be either 'Allow' or 'Deny'."
  }
}

variable "workspace_settings" {
  description = "Configuration settings for Amazon Q Developer workspace integration"
  type = object({
    enable_code_suggestions    = optional(bool, true)
    enable_security_scanning   = optional(bool, true)
    enable_code_explanations   = optional(bool, true)
    suggestion_threshold       = optional(string, "medium")
    max_suggestions_per_minute = optional(number, 50)
  })
  default = {}
  
  validation {
    condition = contains(["low", "medium", "high"], var.workspace_settings.suggestion_threshold)
    error_message = "Suggestion threshold must be one of: low, medium, high."
  }
  
  validation {
    condition = var.workspace_settings.max_suggestions_per_minute >= 1 && var.workspace_settings.max_suggestions_per_minute <= 200
    error_message = "Max suggestions per minute must be between 1 and 200."
  }
}

# Backup and Recovery Variables

variable "enable_backup" {
  description = "Whether to enable backup for Amazon Q Developer configuration"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain Amazon Q Developer configuration backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Integration Configuration Variables

variable "external_integrations" {
  description = "Configuration for external tool integrations with Amazon Q Developer"
  type = map(object({
    enabled      = bool
    endpoint_url = optional(string)
    api_version  = optional(string)
    auth_method  = optional(string, "none")
  }))
  default = {}
  
  validation {
    condition = alltrue([
      for k, v in var.external_integrations : contains(["none", "api_key", "oauth", "iam"], v.auth_method)
    ])
    error_message = "Auth method must be one of: none, api_key, oauth, iam."
  }
}