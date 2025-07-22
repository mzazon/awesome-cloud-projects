# Core configuration variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "compliance-audit"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# QLDB Configuration
variable "qldb_ledger_name" {
  description = "Name for the QLDB ledger"
  type        = string
  default     = null
}

variable "qldb_permissions_mode" {
  description = "Permissions mode for QLDB ledger"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains(["ALLOW_ALL", "STANDARD"], var.qldb_permissions_mode)
    error_message = "QLDB permissions mode must be either ALLOW_ALL or STANDARD."
  }
}

variable "qldb_deletion_protection" {
  description = "Enable deletion protection for QLDB ledger"
  type        = bool
  default     = true
}

# CloudTrail Configuration
variable "cloudtrail_name" {
  description = "Name for the CloudTrail"
  type        = string
  default     = null
}

variable "enable_cloudtrail_log_file_validation" {
  description = "Enable log file validation for CloudTrail"
  type        = bool
  default     = true
}

variable "cloudtrail_include_global_service_events" {
  description = "Include global service events in CloudTrail"
  type        = bool
  default     = true
}

variable "cloudtrail_is_multi_region_trail" {
  description = "Enable multi-region trail for CloudTrail"
  type        = bool
  default     = true
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (will be generated if not provided)"
  type        = string
  default     = null
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket even if not empty"
  type        = bool
  default     = false
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = null
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60

  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
  default     = "your-email@example.com"

  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

# Kinesis Data Firehose Configuration
variable "firehose_delivery_stream_name" {
  description = "Name for the Kinesis Data Firehose delivery stream"
  type        = string
  default     = null
}

variable "firehose_buffer_size" {
  description = "Buffer size in MB for Kinesis Data Firehose"
  type        = number
  default     = 5

  validation {
    condition = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Buffer interval in seconds for Kinesis Data Firehose"
  type        = number
  default     = 300

  validation {
    condition = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

# Athena Configuration
variable "athena_workgroup_name" {
  description = "Name for the Athena workgroup"
  type        = string
  default     = null
}

variable "athena_database_name" {
  description = "Name for the Athena database"
  type        = string
  default     = "compliance_audit_db"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.athena_database_name))
    error_message = "Athena database name must contain only lowercase letters, numbers, and underscores."
  }
}

# Monitoring Configuration
variable "cloudwatch_dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = null
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for resources"
  type        = bool
  default     = true
}

# EventBridge Configuration
variable "eventbridge_rule_name" {
  description = "Name for the EventBridge rule"
  type        = string
  default     = "compliance-audit-rule"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}