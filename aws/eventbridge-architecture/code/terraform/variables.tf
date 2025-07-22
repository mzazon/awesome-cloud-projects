variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "eventbridge-architecture"
}

variable "custom_event_bus_name" {
  description = "Name of the custom EventBridge event bus"
  type        = string
  default     = "ecommerce-events"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for event processing"
  type        = string
  default     = "event-processor"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = can(regex("^python3\\.(8|9|10|11|12)$", var.lambda_runtime))
    error_message = "Lambda runtime must be a supported Python version (python3.8, python3.9, python3.10, python3.11, or python3.12)."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  type        = string
  default     = "order-notifications"
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue for event processing"
  type        = string
  default     = "event-processing"
}

variable "sqs_visibility_timeout" {
  description = "Visibility timeout for the SQS queue in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "sqs_message_retention_period" {
  description = "Message retention period for the SQS queue in seconds"
  type        = number
  default     = 1209600  # 14 days
  
  validation {
    condition     = var.sqs_message_retention_period >= 60 && var.sqs_message_retention_period <= 1209600
    error_message = "SQS message retention period must be between 60 and 1209600 seconds."
  }
}

variable "high_value_order_threshold" {
  description = "Threshold amount for high-value orders"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.high_value_order_threshold > 0
    error_message = "High value order threshold must be greater than 0."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda function"
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch logs retention period."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable X-Ray tracing for Lambda function"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}