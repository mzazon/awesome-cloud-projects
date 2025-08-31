# Variables for Blue-Green Deployment with VPC Lattice and Lambda

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1' or similar."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "ecommerce-api"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "blue_lambda_memory_size" {
  description = "Memory allocation for the blue Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.blue_lambda_memory_size >= 128 && var.blue_lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "green_lambda_memory_size" {
  description = "Memory allocation for the green Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.green_lambda_memory_size >= 128 && var.green_lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "initial_blue_weight" {
  description = "Initial traffic weight for blue environment (0-100)"
  type        = number
  default     = 90

  validation {
    condition     = var.initial_blue_weight >= 0 && var.initial_blue_weight <= 100
    error_message = "Blue weight must be between 0 and 100."
  }
}

variable "initial_green_weight" {
  description = "Initial traffic weight for green environment (0-100)"
  type        = number
  default     = 10

  validation {
    condition     = var.initial_green_weight >= 0 && var.initial_green_weight <= 100
    error_message = "Green weight must be between 0 and 100."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch value."
  }
}

variable "alarm_error_threshold" {
  description = "Error count threshold for CloudWatch alarms"
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_error_threshold > 0
    error_message = "Error threshold must be greater than 0."
  }
}

variable "alarm_duration_threshold" {
  description = "Duration threshold in milliseconds for CloudWatch alarms"
  type        = number
  default     = 10000

  validation {
    condition     = var.alarm_duration_threshold > 0
    error_message = "Duration threshold must be greater than 0."
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

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}