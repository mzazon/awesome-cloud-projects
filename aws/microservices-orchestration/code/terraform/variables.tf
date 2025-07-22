# Input Variables
# This file defines all input variables for the event-driven microservices infrastructure

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "microservices-demo"
  
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PROVISIONED"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
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
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "step_functions_log_level" {
  description = "Step Functions logging level"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions and Step Functions"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring with CloudWatch dashboards and alarms"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}