# Variables for Interactive Data Analytics with Bedrock AgentCore Code Interpreter

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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
  default     = "analytics"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function"
  type        = number
  default     = 10
  validation {
    condition     = var.lambda_reserved_concurrency >= 1 && var.lambda_reserved_concurrency <= 1000
    error_message = "Reserved concurrency must be between 1 and 1000."
  }
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning objects to Infrequent Access"
  type        = number
  default     = 30
  validation {
    condition     = var.s3_lifecycle_transition_days >= 1
    error_message = "Lifecycle transition days must be at least 1."
  }
}

variable "s3_glacier_transition_days" {
  description = "Number of days before transitioning objects to Glacier"
  type        = number
  default     = 90
  validation {
    condition     = var.s3_glacier_transition_days >= 1
    error_message = "Glacier transition days must be at least 1."
  }
}

variable "s3_results_expiration_days" {
  description = "Number of days before expiring result objects"
  type        = number
  default     = 365
  validation {
    condition     = var.s3_results_expiration_days >= 1
    error_message = "Results expiration days must be at least 1."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Evaluation periods must be between 1 and 5."
  }
}

variable "alarm_threshold_errors" {
  description = "Error threshold for CloudWatch alarm"
  type        = number
  default     = 3
  validation {
    condition     = var.alarm_threshold_errors >= 1
    error_message = "Error threshold must be at least 1."
  }
}

variable "code_interpreter_session_timeout" {
  description = "Code interpreter session timeout in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.code_interpreter_session_timeout >= 300 && var.code_interpreter_session_timeout <= 7200
    error_message = "Session timeout must be between 300 and 7200 seconds."
  }
}

variable "api_gateway_throttle_rate" {
  description = "API Gateway throttle rate (requests per second)"
  type        = number
  default     = 100
  validation {
    condition     = var.api_gateway_throttle_rate >= 1
    error_message = "Throttle rate must be at least 1 request per second."
  }
}

variable "api_gateway_throttle_burst" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 200
  validation {
    condition     = var.api_gateway_throttle_burst >= 1
    error_message = "Throttle burst must be at least 1."
  }
}

variable "enable_api_gateway" {
  description = "Whether to create API Gateway for external access"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Whether to enable X-Ray tracing for Lambda"
  type        = bool
  default     = false
}

variable "enable_detailed_monitoring" {
  description = "Whether to enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for AI operations"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.bedrock_model_id))
    error_message = "Bedrock model ID must contain only alphanumeric characters, dots, underscores, and hyphens."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}