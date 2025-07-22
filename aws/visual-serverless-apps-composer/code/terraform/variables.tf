# Core Configuration Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "The AWS region must be in the format 'us-east-1' or similar."
  }
}

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
  description = "Name of the project for resource naming"
  type        = string
  default     = "visual-serverless-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Lambda Configuration Variables
variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency limit for Lambda functions"
  type        = number
  default     = 100
  
  validation {
    condition     = var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000
    error_message = "Lambda reserved concurrency must be between 0 and 1000."
  }
}

# API Gateway Configuration Variables
variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "api_gateway_throttle_rate_limit" {
  description = "Rate limit for API Gateway throttling (requests per second)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.api_gateway_throttle_rate_limit >= 1
    error_message = "API Gateway throttle rate limit must be at least 1."
  }
}

variable "api_gateway_throttle_burst_limit" {
  description = "Burst limit for API Gateway throttling"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.api_gateway_throttle_burst_limit >= 1
    error_message = "API Gateway throttle burst limit must be at least 1."
  }
}

# DynamoDB Configuration Variables
variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

# SQS Configuration Variables
variable "sqs_message_retention_seconds" {
  description = "Message retention period for SQS dead letter queue (in seconds)"
  type        = number
  default     = 1209600  # 14 days
  
  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "SQS message retention must be between 60 seconds and 14 days."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout for SQS dead letter queue (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.sqs_visibility_timeout_seconds >= 0 && var.sqs_visibility_timeout_seconds <= 43200
    error_message = "SQS visibility timeout must be between 0 and 12 hours."
  }
}

# CloudWatch Configuration Variables
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

# Security Configuration Variables
variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions and API Gateway"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for API Gateway"
  type        = bool
  default     = true
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "List of allowed headers for CORS configuration"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# Resource Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Cost Optimization Variables
variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda functions"
  type        = string
  default     = "x86_64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be either x86_64 or arm64."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Lambda functions"
  type        = bool
  default     = false
}