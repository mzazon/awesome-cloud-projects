# =============================================================================
# Simple Application Configuration with AppConfig and Lambda - Variables
# 
# This file defines all input variables for the Terraform configuration,
# including default values and validation rules.
# =============================================================================

# =============================================================================
# General Configuration Variables
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "environment_name" {
  description = "Name for the AppConfig environment"
  type        = string
  default     = "development"
  
  validation {
    condition     = length(var.environment_name) >= 1 && length(var.environment_name) <= 64
    error_message = "Environment name must be between 1 and 64 characters."
  }
}

# =============================================================================
# Naming Configuration Variables
# =============================================================================

variable "app_name_prefix" {
  description = "Prefix for AppConfig application name"
  type        = string
  default     = "simple-config-app"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.app_name_prefix))
    error_message = "App name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_function_prefix" {
  description = "Prefix for Lambda function name"
  type        = string
  default     = "config-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_prefix))
    error_message = "Lambda function prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_role_prefix" {
  description = "Prefix for Lambda IAM role name"
  type        = string
  default     = "lambda-appconfig-role"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_+=,.@]+$", var.lambda_role_prefix))
    error_message = "Lambda role prefix must contain only valid IAM role name characters."
  }
}

# =============================================================================
# Application Configuration Data Variables
# =============================================================================

variable "database_max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 100
  
  validation {
    condition     = var.database_max_connections >= 1 && var.database_max_connections <= 1000
    error_message = "Database max connections must be between 1 and 1000."
  }
}

variable "database_timeout_seconds" {
  description = "Database connection timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.database_timeout_seconds >= 1 && var.database_timeout_seconds <= 300
    error_message = "Database timeout must be between 1 and 300 seconds."
  }
}

variable "database_retry_attempts" {
  description = "Number of database retry attempts"
  type        = number
  default     = 3
  
  validation {
    condition     = var.database_retry_attempts >= 0 && var.database_retry_attempts <= 10
    error_message = "Database retry attempts must be between 0 and 10."
  }
}

variable "features_enable_logging" {
  description = "Enable application logging feature"
  type        = bool
  default     = true
}

variable "features_enable_metrics" {
  description = "Enable application metrics feature"
  type        = bool
  default     = true
}

variable "features_debug_mode" {
  description = "Enable debug mode feature"
  type        = bool
  default     = false
}

variable "api_rate_limit" {
  description = "API rate limit per second"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.api_rate_limit >= 1 && var.api_rate_limit <= 10000
    error_message = "API rate limit must be between 1 and 10000."
  }
}

variable "api_cache_ttl" {
  description = "API cache TTL in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.api_cache_ttl >= 0 && var.api_cache_ttl <= 3600
    error_message = "API cache TTL must be between 0 and 3600 seconds."
  }
}

# =============================================================================
# AppConfig Deployment Strategy Variables
# =============================================================================

variable "deployment_duration_minutes" {
  description = "Duration of configuration deployment in minutes"
  type        = number
  default     = 0
  
  validation {
    condition     = var.deployment_duration_minutes >= 0 && var.deployment_duration_minutes <= 1440
    error_message = "Deployment duration must be between 0 and 1440 minutes (24 hours)."
  }
}

variable "final_bake_time_minutes" {
  description = "Final bake time after deployment completion in minutes"
  type        = number
  default     = 0
  
  validation {
    condition     = var.final_bake_time_minutes >= 0 && var.final_bake_time_minutes <= 1440
    error_message = "Final bake time must be between 0 and 1440 minutes (24 hours)."
  }
}

variable "growth_factor" {
  description = "Percentage of targets to receive deployed configuration during each interval"
  type        = number
  default     = 100
  
  validation {
    condition     = var.growth_factor >= 1 && var.growth_factor <= 100
    error_message = "Growth factor must be between 1 and 100 percent."
  }
}

variable "growth_type" {
  description = "Algorithm used to define how percentage grows over time"
  type        = string
  default     = "LINEAR"
  
  validation {
    condition     = contains(["LINEAR", "EXPONENTIAL"], var.growth_type)
    error_message = "Growth type must be either LINEAR or EXPONENTIAL."
  }
}

# =============================================================================
# Lambda Configuration Variables
# =============================================================================

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x",
      "java8.al2", "java11", "java17", "java21",
      "dotnet6", "dotnet8",
      "go1.x", "provided.al2", "provided.al2023"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
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
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

variable "lambda_log_format" {
  description = "Lambda function log format"
  type        = string
  default     = "JSON"
  
  validation {
    condition     = contains(["Text", "JSON"], var.lambda_log_format)
    error_message = "Lambda log format must be either Text or JSON."
  }
}

variable "lambda_app_log_level" {
  description = "Lambda application log level"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.lambda_app_log_level)
    error_message = "Lambda application log level must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
}

variable "lambda_system_log_level" {
  description = "Lambda system log level"
  type        = string
  default     = "WARN"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN"], var.lambda_system_log_level)
    error_message = "Lambda system log level must be one of: DEBUG, INFO, WARN."
  }
}

variable "log_level" {
  description = "Application log level environment variable"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

# =============================================================================
# CloudWatch Configuration Variables
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = false
}

# =============================================================================
# Feature Flags Variables
# =============================================================================

variable "enable_json_validation" {
  description = "Enable JSON schema validation for configuration profiles"
  type        = bool
  default     = true
}

variable "create_function_url" {
  description = "Create a Lambda function URL for easy testing"
  type        = bool
  default     = false
}

# =============================================================================
# Advanced Configuration Variables
# =============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Cannot apply more than 50 tags to resources."
  }
}