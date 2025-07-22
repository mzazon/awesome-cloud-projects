# Core configuration variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "websocket-api"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# WebSocket API Configuration
variable "api_name" {
  description = "Name for the WebSocket API"
  type        = string
  default     = "websocket-api"
}

variable "api_description" {
  description = "Description for the WebSocket API"
  type        = string
  default     = "Advanced WebSocket API with route management and connection handling"
}

variable "stage_name" {
  description = "Stage name for API deployment"
  type        = string
  default     = "staging"
}

variable "route_selection_expression" {
  description = "Route selection expression for WebSocket API"
  type        = string
  default     = "$request.body.type"
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PROVISIONED"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

variable "enable_dynamodb_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery"
  type        = bool
  default     = true
}

variable "dynamodb_table_class" {
  description = "DynamoDB table class"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.dynamodb_table_class)
    error_message = "DynamoDB table class must be either STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_message_timeout" {
  description = "Lambda message handler timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_message_timeout >= 1 && var.lambda_message_timeout <= 900
    error_message = "Lambda message timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_message_memory_size" {
  description = "Lambda message handler memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_message_memory_size >= 128 && var.lambda_message_memory_size <= 10240
    error_message = "Lambda message memory size must be between 128 and 10240 MB."
  }
}

# API Gateway Configuration
variable "enable_detailed_metrics" {
  description = "Enable detailed metrics for API Gateway"
  type        = bool
  default     = true
}

variable "enable_data_trace" {
  description = "Enable data trace for API Gateway"
  type        = bool
  default     = true
}

variable "logging_level" {
  description = "Logging level for API Gateway"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be one of: OFF, ERROR, INFO."
  }
}

variable "throttling_burst_limit" {
  description = "Throttling burst limit for API Gateway"
  type        = number
  default     = 500
  
  validation {
    condition     = var.throttling_burst_limit >= 0 && var.throttling_burst_limit <= 5000
    error_message = "Throttling burst limit must be between 0 and 5000."
  }
}

variable "throttling_rate_limit" {
  description = "Throttling rate limit for API Gateway"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.throttling_rate_limit >= 0 && var.throttling_rate_limit <= 10000
    error_message = "Throttling rate limit must be between 0 and 10000."
  }
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for DynamoDB tables"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Custom Routes Configuration
variable "custom_routes" {
  description = "Custom routes to create in addition to default routes"
  type        = list(string)
  default     = ["chat", "join_room", "leave_room", "private_message", "room_list"]
  
  validation {
    condition     = length(var.custom_routes) <= 10
    error_message = "Maximum of 10 custom routes are allowed."
  }
}