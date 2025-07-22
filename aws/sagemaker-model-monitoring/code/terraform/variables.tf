# Core AWS configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
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

# Resource naming and identification
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "model-monitor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_suffix" {
  description = "Random suffix for resource names (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# S3 bucket configuration
variable "s3_bucket_versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_force_destroy" {
  description = "Allow force destroy of S3 bucket (useful for testing)"
  type        = bool
  default     = false
}

# SageMaker model configuration
variable "model_instance_type" {
  description = "Instance type for SageMaker model endpoint"
  type        = string
  default     = "ml.t2.medium"
  
  validation {
    condition = can(regex("^ml\\.", var.model_instance_type))
    error_message = "Model instance type must be a valid SageMaker instance type (start with 'ml.')."
  }
}

variable "model_initial_instance_count" {
  description = "Initial number of instances for the SageMaker endpoint"
  type        = number
  default     = 1
  
  validation {
    condition     = var.model_initial_instance_count >= 1 && var.model_initial_instance_count <= 10
    error_message = "Initial instance count must be between 1 and 10."
  }
}

variable "data_capture_sampling_percentage" {
  description = "Percentage of data to capture (0-100)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.data_capture_sampling_percentage >= 0 && var.data_capture_sampling_percentage <= 100
    error_message = "Data capture sampling percentage must be between 0 and 100."
  }
}

# Monitoring configuration
variable "monitoring_instance_type" {
  description = "Instance type for monitoring processing jobs"
  type        = string
  default     = "ml.m5.xlarge"
  
  validation {
    condition = can(regex("^ml\\.", var.monitoring_instance_type))
    error_message = "Monitoring instance type must be a valid SageMaker instance type (start with 'ml.')."
  }
}

variable "monitoring_instance_count" {
  description = "Number of instances for monitoring processing jobs"
  type        = number
  default     = 1
  
  validation {
    condition     = var.monitoring_instance_count >= 1 && var.monitoring_instance_count <= 5
    error_message = "Monitoring instance count must be between 1 and 5."
  }
}

variable "monitoring_volume_size_gb" {
  description = "Volume size in GB for monitoring processing jobs"
  type        = number
  default     = 20
  
  validation {
    condition     = var.monitoring_volume_size_gb >= 20 && var.monitoring_volume_size_gb <= 100
    error_message = "Monitoring volume size must be between 20 and 100 GB."
  }
}

variable "data_quality_schedule_expression" {
  description = "Cron expression for data quality monitoring schedule"
  type        = string
  default     = "cron(0 * * * ? *)"  # Hourly
}

variable "model_quality_schedule_expression" {
  description = "Cron expression for model quality monitoring schedule"
  type        = string
  default     = "cron(0 6 * * ? *)"  # Daily at 6 AM
}

# Lambda configuration
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
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for monitoring alerts (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# CloudWatch alarm configuration
variable "constraint_violation_threshold" {
  description = "Threshold for constraint violation alarms"
  type        = number
  default     = 1
  
  validation {
    condition     = var.constraint_violation_threshold >= 1
    error_message = "Constraint violation threshold must be at least 1."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 1
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "alarm_period_seconds" {
  description = "Period in seconds for CloudWatch alarms"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period_seconds)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600 seconds."
  }
}

# Enable/disable features
variable "enable_model_quality_monitoring" {
  description = "Enable model quality monitoring schedule"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

variable "enable_email_notifications" {
  description = "Enable email notifications for alerts"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}