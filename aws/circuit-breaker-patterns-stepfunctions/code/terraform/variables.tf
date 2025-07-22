# Input Variables for Circuit Breaker Pattern Implementation
# These variables allow customization of the circuit breaker deployment

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
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "circuit-breaker"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "circuit_breaker_failure_threshold" {
  description = "Number of failures before circuit breaker opens"
  type        = number
  default     = 3
  
  validation {
    condition = var.circuit_breaker_failure_threshold > 0 && var.circuit_breaker_failure_threshold <= 10
    error_message = "Failure threshold must be between 1 and 10."
  }
}

variable "downstream_service_failure_rate" {
  description = "Simulated failure rate for downstream service (0.0 to 1.0)"
  type        = number
  default     = 0.5
  
  validation {
    condition = var.downstream_service_failure_rate >= 0.0 && var.downstream_service_failure_rate <= 1.0
    error_message = "Failure rate must be between 0.0 and 1.0."
  }
}

variable "downstream_service_latency_ms" {
  description = "Simulated latency for downstream service in milliseconds"
  type        = number
  default     = 200
  
  validation {
    condition = var.downstream_service_latency_ms >= 0 && var.downstream_service_latency_ms <= 30000
    error_message = "Latency must be between 0 and 30000 milliseconds."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 128
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 5
  
  validation {
    condition = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 5
  
  validation {
    condition = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "sns_email_notification" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_notification == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_notification))
    error_message = "SNS email must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}