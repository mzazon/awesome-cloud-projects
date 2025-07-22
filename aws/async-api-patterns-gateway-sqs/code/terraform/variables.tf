# Input variables for the asynchronous API patterns infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "async-api"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
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

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.api_stage_name))
    error_message = "API stage name must start with a letter and contain only alphanumeric characters."
  }
}

variable "sqs_message_retention_period" {
  description = "SQS message retention period in seconds (60-1209600)"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.sqs_message_retention_period >= 60 && var.sqs_message_retention_period <= 1209600
    error_message = "SQS message retention period must be between 60 and 1209600 seconds."
  }
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds (0-43200)"
  type        = number
  default     = 300 # 5 minutes

  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "sqs_max_receive_count" {
  description = "Maximum number of times a message can be received before moving to DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.sqs_max_receive_count >= 1 && var.sqs_max_receive_count <= 1000
    error_message = "SQS max receive count must be between 1 and 1000."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (1-900)"
  type        = number
  default     = 300 # 5 minutes

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB (128-10240)"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11",
      "nodejs18.x", "nodejs20.x",
      "java11", "java17", "java21",
      "dotnet6", "dotnet8",
      "go1.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 5000

  validation {
    condition     = var.api_throttle_burst_limit >= 0
    error_message = "API throttle burst limit must be non-negative."
  }
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttling rate limit (requests per second)"
  type        = number
  default     = 2000

  validation {
    condition     = var.api_throttle_rate_limit >= 0
    error_message = "API throttle rate limit must be non-negative."
  }
}

variable "lambda_event_source_batch_size" {
  description = "SQS event source mapping batch size (1-10)"
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_event_source_batch_size >= 1 && var.lambda_event_source_batch_size <= 10
    error_message = "Lambda event source batch size must be between 1 and 10."
  }
}

variable "lambda_event_source_max_batching_window" {
  description = "SQS event source mapping maximum batching window in seconds (0-300)"
  type        = number
  default     = 5

  validation {
    condition     = var.lambda_event_source_max_batching_window >= 0 && var.lambda_event_source_max_batching_window <= 300
    error_message = "Lambda event source maximum batching window must be between 0 and 300 seconds."
  }
}

variable "enable_cors" {
  description = "Enable CORS for API Gateway endpoints"
  type        = bool
  default     = true
}

variable "cors_allow_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "CORS allowed methods"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "CORS allowed headers"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

variable "s3_bucket_name_override" {
  description = "Override for S3 bucket name (leave empty for auto-generated name)"
  type        = string
  default     = ""

  validation {
    condition = var.s3_bucket_name_override == "" || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.s3_bucket_name_override))
    error_message = "S3 bucket name must be lowercase, start and end with alphanumeric characters, and contain only hyphens as special characters."
  }
}

variable "enable_encryption" {
  description = "Enable encryption for SQS queues and S3 bucket"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}