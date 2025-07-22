# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "edge-computing-greengrass"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# IoT Thing Configuration
variable "thing_name_prefix" {
  description = "Prefix for IoT Thing name (will be combined with random suffix)"
  type        = string
  default     = "greengrass-core"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.thing_name_prefix))
    error_message = "Thing name prefix must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "thing_group_name_prefix" {
  description = "Prefix for IoT Thing Group name (will be combined with random suffix)"
  type        = string
  default     = "greengrass-things"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.thing_group_name_prefix))
    error_message = "Thing group name prefix must contain only alphanumeric characters, underscores, and hyphens."
  }
}

# Lambda Function Configuration
variable "lambda_function_name_prefix" {
  description = "Prefix for Lambda function name (will be combined with random suffix)"
  type        = string
  default     = "edge-processor"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.lambda_function_name_prefix))
    error_message = "Lambda function name prefix must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs16.x", "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Greengrass Configuration
variable "greengrass_nucleus_version" {
  description = "Version of Greengrass Nucleus component"
  type        = string
  default     = "2.12.0"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.greengrass_nucleus_version))
    error_message = "Greengrass Nucleus version must be in semantic versioning format (e.g., 2.12.0)."
  }
}

variable "enable_stream_manager" {
  description = "Enable Stream Manager component for data routing"
  type        = bool
  default     = true
}

variable "stream_manager_version" {
  description = "Version of Stream Manager component"
  type        = string
  default     = "2.1.7"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.stream_manager_version))
    error_message = "Stream Manager version must be in semantic versioning format (e.g., 2.1.7)."
  }
}

# Security Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for Greengrass Core device"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# IoT Policy Configuration
variable "iot_policy_actions" {
  description = "List of IoT actions to allow in the policy"
  type        = list(string)
  default = [
    "iot:Publish",
    "iot:Subscribe",
    "iot:Receive",
    "iot:Connect",
    "greengrass:*"
  ]
  
  validation {
    condition     = length(var.iot_policy_actions) > 0
    error_message = "IoT policy actions list cannot be empty."
  }
}

# Component Configuration
variable "custom_component_version" {
  description = "Version for custom Lambda component"
  type        = string
  default     = "1.0.0"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.custom_component_version))
    error_message = "Component version must be in semantic versioning format (e.g., 1.0.0)."
  }
}

# Resource Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9\\s\\._:/=+\\-@]+$", k))
    ])
    error_message = "Tag keys must contain only valid characters."
  }
}