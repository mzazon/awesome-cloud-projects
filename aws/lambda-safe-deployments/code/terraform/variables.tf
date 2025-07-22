# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
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

# Lambda Function Configuration
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "deployment-patterns-demo"
}

variable "lambda_runtime" {
  description = "Lambda runtime for the function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# API Gateway Configuration
variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
  default     = "deployment-api"
}

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "api_description" {
  description = "Description for the API Gateway"
  type        = string
  default     = "API for Lambda deployment patterns demonstration"
}

# Deployment Configuration
variable "canary_traffic_percentage" {
  description = "Percentage of traffic to route to canary version (0-100)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.canary_traffic_percentage >= 0 && var.canary_traffic_percentage <= 100
    error_message = "Canary traffic percentage must be between 0 and 100."
  }
}

variable "enable_canary_deployment" {
  description = "Enable canary deployment with weighted traffic routing"
  type        = bool
  default     = true
}

variable "enable_blue_green_deployment" {
  description = "Enable blue-green deployment pattern"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid retention period."
  }
}

variable "error_alarm_threshold" {
  description = "Threshold for error rate alarm"
  type        = number
  default     = 5
}

variable "error_alarm_evaluation_periods" {
  description = "Number of evaluation periods for error rate alarm"
  type        = number
  default     = 2
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "lambda-deploy"
}

variable "use_random_suffix" {
  description = "Add random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}