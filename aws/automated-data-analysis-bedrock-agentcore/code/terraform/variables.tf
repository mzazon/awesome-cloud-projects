# Variables for Automated Data Analysis with Bedrock AgentCore Runtime
# These variables allow customization of the infrastructure deployment

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "data-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_force_destroy" {
  description = "Allow S3 buckets to be destroyed even if they contain objects"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

variable "dataset_prefix" {
  description = "S3 prefix for dataset uploads that trigger analysis"
  type        = string
  default     = "datasets/"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/$", var.dataset_prefix))
    error_message = "Dataset prefix must end with a slash and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "enable_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}