# Input variables for the AgentCore Performance Monitoring infrastructure
# These variables allow customization of the deployment

# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Agent Configuration
variable "agent_name" {
  description = "Name of the AgentCore agent to monitor"
  type        = string
  default     = ""
  
  validation {
    condition = var.agent_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.agent_name))
    error_message = "Agent name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6
  
  validation {
    condition = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# S3 Configuration
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "agent-monitoring-data"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle policies on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_expiration_days" {
  description = "Number of days after which S3 objects expire"
  type        = number
  default     = 90
  
  validation {
    condition = var.s3_expiration_days >= 30 && var.s3_expiration_days <= 365
    error_message = "S3 expiration days must be between 30 and 365."
  }
}

# Lambda Configuration
variable "lambda_function_prefix" {
  description = "Prefix for Lambda function name"
  type        = string
  default     = "agent-performance-optimizer"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_prefix))
    error_message = "Lambda function prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.lambda_log_retention_days)
    error_message = "Lambda log retention days must be a valid CloudWatch Logs retention period."
  }
}

# CloudWatch Alarm Configuration
variable "latency_threshold_ms" {
  description = "Latency threshold in milliseconds for CloudWatch alarm"
  type        = number
  default     = 30000
  
  validation {
    condition = var.latency_threshold_ms >= 1000 && var.latency_threshold_ms <= 300000
    error_message = "Latency threshold must be between 1000 and 300000 milliseconds."
  }
}

variable "system_error_threshold" {
  description = "System error threshold for CloudWatch alarm"
  type        = number
  default     = 5
  
  validation {
    condition = var.system_error_threshold >= 1 && var.system_error_threshold <= 100
    error_message = "System error threshold must be between 1 and 100."
  }
}

variable "throttle_threshold" {
  description = "Throttle threshold for CloudWatch alarm"
  type        = number
  default     = 10
  
  validation {
    condition = var.throttle_threshold >= 1 && var.throttle_threshold <= 100
    error_message = "Throttle threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period_seconds" {
  description = "Period in seconds for CloudWatch alarm metrics"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600, 21600, 86400], var.alarm_period_seconds)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

# Dashboard Configuration
variable "create_dashboard" {
  description = "Whether to create CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "dashboard_name_prefix" {
  description = "Prefix for CloudWatch dashboard name"
  type        = string
  default     = "AgentCore-Performance"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.dashboard_name_prefix))
    error_message = "Dashboard name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# IAM Configuration
variable "agentcore_role_prefix" {
  description = "Prefix for AgentCore IAM role name"
  type        = string
  default     = "AgentCoreMonitoringRole"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.agentcore_role_prefix))
    error_message = "AgentCore role prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_role_prefix" {
  description = "Prefix for Lambda IAM role name"
  type        = string
  default     = "LambdaPerformanceMonitorRole"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_role_prefix))
    error_message = "Lambda role prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}