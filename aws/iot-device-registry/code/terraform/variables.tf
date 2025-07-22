# Variable definitions for IoT Device Management Infrastructure
# These variables allow customization of the deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "iot-device-mgmt"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "iot_thing_type_name" {
  description = "Name of the IoT Thing Type for device categorization"
  type        = string
  default     = "TemperatureSensor"

  validation {
    condition = length(var.iot_thing_type_name) <= 128
    error_message = "IoT Thing Type name must be 128 characters or less."
  }
}

variable "device_attributes" {
  description = "Default attributes for IoT devices"
  type        = map(string)
  default = {
    deviceType   = "temperature"
    manufacturer = "SensorCorp"
    model        = "TC-2000"
    location     = "ProductionFloor-A"
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30

  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 128

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "temperature_threshold" {
  description = "Temperature threshold for alerts (in Celsius)"
  type        = number
  default     = 80

  validation {
    condition = var.temperature_threshold >= -50 && var.temperature_threshold <= 150
    error_message = "Temperature threshold must be between -50 and 150 degrees Celsius."
  }
}

variable "reporting_interval" {
  description = "Device reporting interval in seconds"
  type        = number
  default     = 60

  validation {
    condition = var.reporting_interval >= 10 && var.reporting_interval <= 3600
    error_message = "Reporting interval must be between 10 and 3600 seconds."
  }
}

variable "enable_device_shadow" {
  description = "Whether to enable device shadow functionality"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logging for Lambda"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}