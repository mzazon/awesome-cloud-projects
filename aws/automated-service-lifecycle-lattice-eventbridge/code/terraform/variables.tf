# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "service-lifecycle"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Lattice Configuration
variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = ""
}

variable "service_network_auth_type" {
  description = "Authentication type for the VPC Lattice service network"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.service_network_auth_type)
    error_message = "Auth type must be either NONE or AWS_IAM."
  }
}

# EventBridge Configuration
variable "custom_event_bus_name" {
  description = "Name for the custom EventBridge bus"
  type        = string
  default     = ""
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 60
  
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

# CloudWatch Configuration
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "health_check_schedule" {
  description = "CloudWatch Events schedule expression for health checks"
  type        = string
  default     = "rate(5 minutes)"
  
  validation {
    condition     = can(regex("^(rate|cron)\\(.*\\)$", var.health_check_schedule))
    error_message = "Schedule must be a valid CloudWatch Events schedule expression."
  }
}

# CloudWatch Dashboard Configuration
variable "enable_dashboard" {
  description = "Whether to create a CloudWatch dashboard"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}