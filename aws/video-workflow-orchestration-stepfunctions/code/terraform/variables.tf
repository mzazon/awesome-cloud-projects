# Input variables for video workflow orchestration infrastructure

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
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "video-workflow"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be 20 characters or less."
  }
}

variable "notification_email" {
  description = "Email address for workflow notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "enable_api_gateway" {
  description = "Whether to create API Gateway for workflow triggering"
  type        = bool
  default     = true
}

variable "enable_s3_triggers" {
  description = "Whether to enable automatic S3 event triggers"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 buckets with objects"
  type        = bool
  default     = false
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch monitoring dashboard"
  type        = bool
  default     = true
}

variable "step_functions_type" {
  description = "Step Functions state machine type (STANDARD or EXPRESS)"
  type        = string
  default     = "EXPRESS"
  
  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.step_functions_type)
    error_message = "Step Functions type must be either STANDARD or EXPRESS."
  }
}

variable "mediaconvert_queue_priority" {
  description = "Priority for MediaConvert queue (0-10, higher is higher priority)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.mediaconvert_queue_priority >= 0 && var.mediaconvert_queue_priority <= 10
    error_message = "MediaConvert queue priority must be between 0 and 10."
  }
}

variable "video_file_extensions" {
  description = "List of video file extensions to trigger workflows"
  type        = list(string)
  default     = ["mp4", "mov", "avi", "mkv"]
  
  validation {
    condition = alltrue([
      for ext in var.video_file_extensions : can(regex("^[a-z0-9]+$", ext))
    ])
    error_message = "Video file extensions must contain only lowercase letters and numbers."
  }
}

variable "quality_threshold" {
  description = "Minimum quality score threshold for publishing (0.0-1.0)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.quality_threshold >= 0.0 && var.quality_threshold <= 1.0
    error_message = "Quality threshold must be between 0.0 and 1.0."
  }
}

variable "enable_cost_alerts" {
  description = "Whether to enable cost monitoring and alerts"
  type        = bool
  default     = false
}

variable "monthly_cost_threshold" {
  description = "Monthly cost threshold in USD for alerts"
  type        = number
  default     = 100.0
  
  validation {
    condition     = var.monthly_cost_threshold > 0
    error_message = "Monthly cost threshold must be greater than 0."
  }
}