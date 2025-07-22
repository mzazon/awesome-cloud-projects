# Input variables for the centralized SaaS security monitoring infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "saas-security-monitor"
  
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
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "ap-northeast-1"
    ], var.aws_region)
    error_message = "AWS AppFabric is only available in us-east-1, us-west-2, eu-west-1, and ap-northeast-1."
  }
}

variable "alert_email" {
  description = "Email address for security alert notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Email address must be valid or empty."
  }
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption with KMS"
  type        = bool
  default     = true
}

variable "s3_bucket_force_destroy" {
  description = "Force destroy S3 bucket even if not empty (use with caution in production)"
  type        = bool
  default     = false
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime version"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "eventbridge_rule_state" {
  description = "State of the EventBridge rule (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.eventbridge_rule_state)
    error_message = "EventBridge rule state must be ENABLED or DISABLED."
  }
}

variable "security_log_prefix" {
  description = "S3 prefix for security log files"
  type        = string
  default     = "security-logs"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-/]+$", var.security_log_prefix))
    error_message = "S3 prefix must contain only alphanumeric characters, hyphens, and forward slashes."
  }
}

variable "appfabric_processing_format" {
  description = "AppFabric log processing format"
  type        = string
  default     = "json"
  
  validation {
    condition     = contains(["json", "parquet"], var.appfabric_processing_format)
    error_message = "AppFabric processing format must be json or parquet."
  }
}

variable "appfabric_processing_schema" {
  description = "AppFabric log processing schema"
  type        = string
  default     = "ocsf"
  
  validation {
    condition     = contains(["ocsf", "raw"], var.appfabric_processing_schema)
    error_message = "AppFabric processing schema must be ocsf or raw."
  }
}

variable "enable_sns_encryption" {
  description = "Enable SNS topic encryption with KMS"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}