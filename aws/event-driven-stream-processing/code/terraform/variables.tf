# Variables for Real-Time Data Processing with Kinesis and Lambda
# This file defines all configurable parameters for the infrastructure deployment.

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "retail-events"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Kinesis Data Stream Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis Data Stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Kinesis shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Retention period must be between 24 and 8760 hours."
  }
}

variable "kinesis_shard_level_metrics" {
  description = "List of shard-level metrics to enable"
  type        = list(string)
  default     = ["IncomingRecords", "OutgoingRecords"]
  
  validation {
    condition = alltrue([
      for metric in var.kinesis_shard_level_metrics :
      contains([
        "IncomingBytes", "IncomingRecords", "OutgoingBytes", 
        "OutgoingRecords", "WriteProvisionedThroughputExceeded",
        "ReadProvisionedThroughputExceeded", "IteratorAgeMilliseconds"
      ], metric)
    ])
    error_message = "Invalid shard-level metric specified."
  }
}

# Lambda Function Configuration
variable "lambda_memory_size" {
  description = "Amount of memory in MB allocated to the Lambda function"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (-1 for unreserved)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.lambda_reserved_concurrency == -1 || var.lambda_reserved_concurrency >= 0
    error_message = "Reserved concurrency must be -1 (unreserved) or >= 0."
  }
}

variable "lambda_batch_size" {
  description = "Maximum number of records per Lambda invocation"
  type        = number
  default     = 100
  
  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 10000
    error_message = "Lambda batch size must be between 1 and 10000."
  }
}

variable "lambda_maximum_batching_window_in_seconds" {
  description = "Maximum time in seconds to wait for batching records"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_maximum_batching_window_in_seconds >= 0 && var.lambda_maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "lambda_starting_position" {
  description = "Starting position for reading from Kinesis stream"
  type        = string
  default     = "LATEST"
  
  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.lambda_starting_position)
    error_message = "Starting position must be either TRIM_HORIZON or LATEST."
  }
}

# DynamoDB Table Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "dynamodb_point_in_time_recovery_enabled" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "dynamodb_server_side_encryption_enabled" {
  description = "Enable server-side encryption for DynamoDB table"
  type        = bool
  default     = true
}

# SQS Dead Letter Queue Configuration
variable "sqs_message_retention_seconds" {
  description = "Message retention period in seconds for the dead letter queue"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "SQS message retention must be between 60 and 1209600 seconds."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout in seconds for SQS messages"
  type        = number
  default     = 30
  
  validation {
    condition     = var.sqs_visibility_timeout_seconds >= 0 && var.sqs_visibility_timeout_seconds <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds."
  }
}

# CloudWatch Alarm Configuration
variable "cloudwatch_alarm_threshold" {
  description = "Threshold for failed events CloudWatch alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloudwatch_alarm_threshold > 0
    error_message = "CloudWatch alarm threshold must be greater than 0."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarm"
  type        = number
  default     = 1
  
  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "CloudWatch alarm evaluation periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period_seconds" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 60
  
  validation {
    condition     = contains([10, 30, 60, 300, 900, 3600, 21600, 86400], var.cloudwatch_alarm_period_seconds)
    error_message = "CloudWatch alarm period must be one of: 10, 30, 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

# SNS Notification Configuration (Optional)
variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}