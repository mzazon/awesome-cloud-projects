# Variables for AWS Sustainability Intelligence Dashboard
# Provides configurable parameters for the sustainability analytics solution

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "sustainability-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "data_lake_bucket_name" {
  description = "Name for the S3 data lake bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name for the Lambda data processing function (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  description = "Lambda runtime version for the data processing function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB (optimized for sustainability)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 MB and 3008 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_architecture" {
  description = "Lambda function architecture (arm64 for better energy efficiency)"
  type        = string
  default     = "arm64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be either x86_64 or arm64."
  }
}

variable "data_processing_schedule" {
  description = "EventBridge schedule expression for automated data processing"
  type        = string
  default     = "rate(30 days)"
  
  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.data_processing_schedule))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring with custom metrics"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which to transition S3 objects to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 30
    error_message = "S3 lifecycle transition must be at least 30 days."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which to delete S3 objects (0 to disable)"
  type        = number
  default     = 2555  # 7 years for compliance retention
  
  validation {
    condition     = var.s3_lifecycle_expiration_days == 0 || var.s3_lifecycle_expiration_days >= 365
    error_message = "S3 lifecycle expiration must be 0 (disabled) or at least 365 days."
  }
}

variable "quicksight_user_arns" {
  description = "List of QuickSight user ARNs to grant dashboard access (optional)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.quicksight_user_arns : can(regex("^arn:aws:quicksight:", arn))
    ])
    error_message = "All QuickSight user ARNs must be valid ARN format."
  }
}

variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.quicksight_edition)
    error_message = "QuickSight edition must be either STANDARD or ENTERPRISE."
  }
}

variable "cost_anomaly_threshold" {
  description = "Cost anomaly detection threshold in USD for sustainability alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.cost_anomaly_threshold > 0
    error_message = "Cost anomaly threshold must be greater than 0."
  }
}

variable "notification_email" {
  description = "Email address for sustainability alert notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for data governance"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete protection for S3 bucket (requires versioning)"
  type        = bool
  default     = false
}

variable "kms_key_rotation" {
  description = "Enable automatic KMS key rotation for encryption"
  type        = bool
  default     = true
}

variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.resource_tags) <= 50
    error_message = "Maximum of 50 additional tags allowed."
  }
}