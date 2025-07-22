# Variables for Infrastructure Policy Validation with CloudFormation Guard
# These variables allow customization of the policy validation infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", 
      "staging", 
      "production", 
      "test"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

variable "team" {
  description = "Team name responsible for the infrastructure"
  type        = string
  default     = "DevOps"
  
  validation {
    condition     = length(var.team) > 0 && length(var.team) <= 50
    error_message = "Team name must be between 1 and 50 characters."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = "CC-1000"
  
  validation {
    condition     = can(regex("^CC-[0-9]{4}$", var.cost_center))
    error_message = "Cost center must follow the format CC-XXXX where X is a digit."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for Guard validations"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 
      365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for validation results"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning on the S3 bucket for Guard rules"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_enabled" {
  description = "Enable lifecycle policies on the S3 bucket for cost optimization"
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Create CloudWatch dashboard for monitoring policy validation"
  type        = bool
  default     = true
}

variable "guard_rules_config" {
  description = "Configuration for Guard rules to be created"
  type = object({
    security_rules = optional(object({
      s3_security_enabled  = optional(bool, true)
      iam_security_enabled = optional(bool, true)
    }), {})
    compliance_rules = optional(object({
      resource_compliance_enabled = optional(bool, true)
      naming_convention_enabled   = optional(bool, true)
    }), {})
    cost_optimization_rules = optional(object({
      ec2_instance_limits_enabled = optional(bool, true)
      rds_limits_enabled          = optional(bool, true)
    }), {})
  })
  default = {}
}

variable "allowed_ec2_instance_types" {
  description = "List of allowed EC2 instance types for cost optimization rules"
  type        = list(string)
  default = [
    "t3.micro",
    "t3.small", 
    "t3.medium",
    "m5.large",
    "m5.xlarge",
    "c5.large",
    "c5.xlarge"
  ]
  
  validation {
    condition     = length(var.allowed_ec2_instance_types) > 0
    error_message = "At least one EC2 instance type must be allowed."
  }
}

variable "allowed_rds_instance_classes" {
  description = "List of allowed RDS instance classes for cost optimization rules"
  type        = list(string)
  default = [
    "db.t3.micro",
    "db.t3.small",
    "db.t3.medium",
    "db.m5.large",
    "db.m5.xlarge"
  ]
  
  validation {
    condition     = length(var.allowed_rds_instance_classes) > 0
    error_message = "At least one RDS instance class must be allowed."
  }
}

variable "required_tags" {
  description = "List of required tags for resource compliance rules"
  type        = list(string)
  default = [
    "Environment",
    "Team", 
    "Project",
    "CostCenter"
  ]
  
  validation {
    condition     = length(var.required_tags) > 0
    error_message = "At least one required tag must be specified."
  }
}

variable "lambda_timeout_limit" {
  description = "Maximum allowed timeout for Lambda functions (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout_limit > 0 && var.lambda_timeout_limit <= 900
    error_message = "Lambda timeout limit must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_min" {
  description = "Minimum allowed memory for Lambda functions (in MB)"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_min >= 128 && var.lambda_memory_min <= 10240
    error_message = "Lambda minimum memory must be between 128 and 10240 MB."
  }
}

variable "lambda_memory_max" {
  description = "Maximum allowed memory for Lambda functions (in MB)"
  type        = number
  default     = 3008
  
  validation {
    condition     = var.lambda_memory_max >= 128 && var.lambda_memory_max <= 10240
    error_message = "Lambda maximum memory must be between 128 and 10240 MB."
  }
}

variable "rds_backup_retention_min" {
  description = "Minimum backup retention period for RDS instances (in days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.rds_backup_retention_min >= 0 && var.rds_backup_retention_min <= 35
    error_message = "RDS backup retention minimum must be between 0 and 35 days."
  }
}

variable "rds_backup_retention_max" {
  description = "Maximum backup retention period for RDS instances (in days)"
  type        = number
  default     = 35
  
  validation {
    condition     = var.rds_backup_retention_max >= 0 && var.rds_backup_retention_max <= 35
    error_message = "RDS backup retention maximum must be between 0 and 35 days."
  }
}

variable "bucket_naming_pattern" {
  description = "Regex pattern for S3 bucket naming convention validation"
  type        = string
  default     = "^[a-z0-9][a-z0-9\\-]*[a-z0-9]$"
  
  validation {
    condition = can(regex(var.bucket_naming_pattern, "valid-bucket-name"))
    error_message = "Bucket naming pattern must be a valid regex pattern."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for tag_key, tag_value in var.additional_tags : 
      length(tag_key) <= 128 && length(tag_value) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and tag values must be <= 256 characters."
  }
}

variable "create_example_templates" {
  description = "Create example CloudFormation templates for testing"
  type        = bool
  default     = true
}

variable "iam_path_prefix" {
  description = "Required path prefix for IAM roles in compliance rules"
  type        = string
  default     = "/[a-zA-Z0-9_-]+/"
  
  validation {
    condition     = can(regex("^/.*/$", var.iam_path_prefix))
    error_message = "IAM path prefix must start and end with forward slashes."
  }
}