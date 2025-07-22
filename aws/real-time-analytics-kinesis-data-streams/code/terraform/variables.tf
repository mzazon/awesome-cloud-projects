# Core Configuration Variables
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
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "kinesis-analytics"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Kinesis Stream Configuration
variable "shard_count" {
  description = "Number of shards for the Kinesis stream"
  type        = number
  default     = 3
  
  validation {
    condition = var.shard_count >= 1 && var.shard_count <= 100
    error_message = "Shard count must be between 1 and 100."
  }
}

variable "retention_period" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 168  # 7 days
  
  validation {
    condition = var.retention_period >= 24 && var.retention_period <= 8760
    error_message = "Retention period must be between 24 hours (1 day) and 8760 hours (365 days)."
  }
}

variable "shard_level_metrics" {
  description = "List of shard-level metrics to enable for enhanced monitoring"
  type        = list(string)
  default     = ["IncomingRecords", "OutgoingRecords", "WriteProvisionedThroughputExceeded", "ReadProvisionedThroughputExceeded", "IteratorAgeMilliseconds"]
  
  validation {
    condition = alltrue([
      for metric in var.shard_level_metrics : contains([
        "IncomingRecords", "OutgoingRecords", "WriteProvisionedThroughputExceeded",
        "ReadProvisionedThroughputExceeded", "IteratorAgeMilliseconds", "IncomingBytes", "OutgoingBytes"
      ], metric)
    ])
    error_message = "All metrics must be valid Kinesis shard-level metrics."
  }
}

# Lambda Function Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
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

variable "batch_size" {
  description = "Maximum number of records to send to Lambda in a single batch"
  type        = number
  default     = 10
  
  validation {
    condition = var.batch_size >= 1 && var.batch_size <= 1000
    error_message = "Batch size must be between 1 and 1000."
  }
}

variable "maximum_batching_window_in_seconds" {
  description = "Maximum amount of time to gather records before invoking Lambda"
  type        = number
  default     = 5
  
  validation {
    condition = var.maximum_batching_window_in_seconds >= 0 && var.maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

# S3 Configuration
variable "s3_bucket_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

# CloudWatch Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Kinesis stream"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Alerting Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "high_incoming_records_threshold" {
  description = "Threshold for high incoming records alarm"
  type        = number
  default     = 1000
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 1
}

variable "alarm_email_endpoints" {
  description = "Email addresses to receive alarm notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alarm_email_endpoints : can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

# Cost Management
variable "enable_cost_allocation_tags" {
  description = "Enable additional tags for cost allocation and management"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner of the resources for billing and management"
  type        = string
  default     = ""
}