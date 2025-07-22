# Variables for IoT Device Provisioning and Certificate Management
# This file defines all configurable parameters for the infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "iot-provisioning"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "device_types" {
  description = "List of supported device types for provisioning"
  type        = list(string)
  default     = ["temperature-sensor", "humidity-sensor", "pressure-sensor", "gateway"]
  
  validation {
    condition = length(var.device_types) > 0
    error_message = "At least one device type must be specified."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alerts"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging for provisioning events"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "alarm_threshold" {
  description = "CloudWatch alarm threshold for failed provisioning attempts"
  type        = number
  default     = 5
  
  validation {
    condition = var.alarm_threshold > 0
    error_message = "Alarm threshold must be greater than 0."
  }
}

variable "sns_endpoint" {
  description = "SNS endpoint for alarm notifications (email address)"
  type        = string
  default     = ""
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}