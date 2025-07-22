# ===================================
# VARIABLES - Dynamic Configuration with Parameter Store
# ===================================
#
# This file defines all configurable variables for the dynamic configuration
# management solution. Variables are organized by category for easy management.

# ===================================
# CORE CONFIGURATION
# ===================================

variable "function_name" {
  description = "Base name of the Lambda function (suffix will be added for uniqueness)"
  type        = string
  default     = "config-manager"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.function_name))
    error_message = "Function name must contain only alphanumeric characters, hyphens, and underscores, and be between 1-50 characters."
  }
}

variable "parameter_prefix" {
  description = "Prefix path for Parameter Store parameters (e.g., /myapp/config)"
  type        = string
  default     = "/myapp/config"
  
  validation {
    condition     = can(regex("^/[a-zA-Z0-9-_/]+[^/]$", var.parameter_prefix))
    error_message = "Parameter prefix must start with '/' and not end with '/', containing only alphanumeric characters, hyphens, underscores, and forward slashes."
  }
}

# ===================================
# LAMBDA CONFIGURATION
# ===================================

variable "lambda_runtime" {
  description = "Runtime version for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version (3.8-3.12)."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "parameters_extension_ttl" {
  description = "TTL (Time To Live) for Parameters and Secrets Extension cache in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.parameters_extension_ttl >= 0 && var.parameters_extension_ttl <= 3600
    error_message = "Parameters extension TTL must be between 0 and 3600 seconds (1 hour)."
  }
}

# ===================================
# APPLICATION CONFIGURATION PARAMETERS
# ===================================

variable "database_host" {
  description = "Database host endpoint for application configuration"
  type        = string
  default     = "myapp-db.cluster-xyz.us-east-1.rds.amazonaws.com"
  
  validation {
    condition     = length(var.database_host) > 0
    error_message = "Database host cannot be empty."
  }
}

variable "database_port" {
  description = "Database port number"
  type        = string
  default     = "5432"
  
  validation {
    condition     = can(tonumber(var.database_port)) && tonumber(var.database_port) >= 1 && tonumber(var.database_port) <= 65535
    error_message = "Database port must be a valid port number between 1 and 65535."
  }
}

variable "database_password" {
  description = "Database password (will be stored as SecureString in Parameter Store)"
  type        = string
  sensitive   = true
  default     = "supersecretpassword123"
  
  validation {
    condition     = length(var.database_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "api_timeout" {
  description = "API timeout in seconds"
  type        = string
  default     = "30"
  
  validation {
    condition     = can(tonumber(var.api_timeout)) && tonumber(var.api_timeout) >= 1 && tonumber(var.api_timeout) <= 300
    error_message = "API timeout must be a valid number between 1 and 300 seconds."
  }
}

variable "feature_new_ui" {
  description = "Feature flag for new UI functionality (true/false)"
  type        = string
  default     = "true"
  
  validation {
    condition     = contains(["true", "false"], var.feature_new_ui)
    error_message = "Feature flag must be either 'true' or 'false'."
  }
}

# ===================================
# MONITORING CONFIGURATION
# ===================================

variable "error_threshold" {
  description = "Error count threshold for CloudWatch alarm (number of errors to trigger alarm)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_threshold >= 1 && var.error_threshold <= 100
    error_message = "Error threshold must be between 1 and 100."
  }
}

variable "duration_threshold" {
  description = "Duration threshold in milliseconds for CloudWatch alarm"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.duration_threshold >= 1000 && var.duration_threshold <= 900000
    error_message = "Duration threshold must be between 1,000 ms (1 second) and 900,000 ms (15 minutes)."
  }
}

variable "failure_threshold" {
  description = "Parameter retrieval failure threshold for CloudWatch alarm"
  type        = number
  default     = 3
  
  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 50
    error_message = "Failure threshold must be between 1 and 50."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for CloudWatch alarm evaluation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, or 3600 seconds."
  }
}

# ===================================
# TAGGING AND METADATA
# ===================================

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ConfigManager"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "DevOps"
    CostCenter  = "Engineering"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Cannot specify more than 50 tags."
  }
}

variable "environment" {
  description = "Environment name (used for resource naming and tagging)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, or test."
  }
}

variable "owner" {
  description = "Owner of the resources (used for tagging and accountability)"
  type        = string
  default     = "DevOps"
  
  validation {
    condition     = length(var.owner) > 0 && length(var.owner) <= 64
    error_message = "Owner must be between 1 and 64 characters."
  }
}

# ===================================
# FEATURE FLAGS
# ===================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for Lambda function"
  type        = bool
  default     = true
}

variable "enable_x_ray_tracing" {
  description = "Enable X-Ray tracing for Lambda function"
  type        = bool
  default     = false
}

variable "create_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "create_alarms" {
  description = "Create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# ===================================
# ADVANCED CONFIGURATION
# ===================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for the Lambda function (null for unreserved)"
  type        = number
  default     = null
  
  validation {
    condition     = var.reserved_concurrent_executions == null || (var.reserved_concurrent_executions >= 0 && var.reserved_concurrent_executions <= 1000)
    error_message = "Reserved concurrent executions must be null or between 0 and 1000."
  }
}

variable "dead_letter_config_enabled" {
  description = "Enable dead letter queue for Lambda function failures"
  type        = bool
  default     = false
}