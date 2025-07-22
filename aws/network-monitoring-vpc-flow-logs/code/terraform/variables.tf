# Variable definitions for VPC Flow Logs monitoring infrastructure

variable "aws_region" {
  description = "AWS region for resources"
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

variable "vpc_id" {
  description = "VPC ID to monitor. If not provided, will use the default VPC"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "vpc-flow-monitoring"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning S3 objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.s3_lifecycle_transition_days >= 30
    error_message = "S3 lifecycle transition days must be at least 30."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring S3 objects"
  type        = number
  default     = 90
  
  validation {
    condition = var.s3_lifecycle_expiration_days > var.s3_lifecycle_transition_days
    error_message = "S3 lifecycle expiration days must be greater than transition days."
  }
}

variable "alarm_rejected_connections_threshold" {
  description = "Threshold for rejected connections alarm"
  type        = number
  default     = 50
  
  validation {
    condition = var.alarm_rejected_connections_threshold > 0
    error_message = "Rejected connections threshold must be greater than 0."
  }
}

variable "alarm_high_data_transfer_threshold" {
  description = "Threshold for high data transfer alarm"
  type        = number
  default     = 10
  
  validation {
    condition = var.alarm_high_data_transfer_threshold > 0
    error_message = "High data transfer threshold must be greater than 0."
  }
}

variable "alarm_external_connections_threshold" {
  description = "Threshold for external connections alarm"
  type        = number
  default     = 100
  
  validation {
    condition = var.alarm_external_connections_threshold > 0
    error_message = "External connections threshold must be greater than 0."
  }
}

variable "notification_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_lambda_analysis" {
  description = "Enable Lambda function for advanced log analysis"
  type        = bool
  default     = true
}

variable "enable_athena_analysis" {
  description = "Enable Athena table for flow logs analysis"
  type        = bool
  default     = true
}

variable "max_aggregation_interval" {
  description = "Maximum aggregation interval for flow logs (60 or 600 seconds)"
  type        = number
  default     = 60
  
  validation {
    condition = contains([60, 600], var.max_aggregation_interval)
    error_message = "Max aggregation interval must be either 60 or 600 seconds."
  }
}

variable "enable_s3_flow_logs" {
  description = "Enable flow logs delivery to S3"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_flow_logs" {
  description = "Enable flow logs delivery to CloudWatch Logs"
  type        = bool
  default     = true
}