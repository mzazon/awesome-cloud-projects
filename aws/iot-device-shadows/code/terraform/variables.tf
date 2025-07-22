# Variables for IoT Device Shadows State Management Infrastructure

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "iot-shadow-demo"
  
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

variable "thing_type_name" {
  description = "IoT Thing Type for the smart thermostat devices"
  type        = string
  default     = "Thermostat"
}

variable "thing_attributes" {
  description = "Default attributes for IoT Things"
  type        = map(string)
  default = {
    manufacturer = "SmartHome"
    model        = "TH-2024"
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs_retention" {
  description = "Enable CloudWatch Logs retention policy"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch Logs retention days must be a valid retention period."
  }
}

variable "initial_shadow_state" {
  description = "Initial state for device shadow"
  type = object({
    reported = object({
      temperature        = number
      humidity          = number
      hvac_mode         = string
      target_temperature = number
      firmware_version   = string
      connectivity       = string
    })
    desired = object({
      target_temperature = number
      hvac_mode         = string
    })
  })
  default = {
    reported = {
      temperature        = 22.5
      humidity          = 45
      hvac_mode         = "heat"
      target_temperature = 23.0
      firmware_version   = "1.2.3"
      connectivity       = "online"
    }
    desired = {
      target_temperature = 23.0
      hvac_mode         = "auto"
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}