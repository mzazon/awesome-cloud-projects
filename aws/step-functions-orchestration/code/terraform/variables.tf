# ===============================================================================
# Terraform Variables for AWS Step Functions Microservices Orchestration
# ===============================================================================
# This file defines all configurable parameters for the microservices
# orchestration infrastructure deployment.
# ===============================================================================

# ===============================================================================
# Project Configuration
# ===============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "microservices-stepfn"
  
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

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Application = "MicroservicesOrchestration"
    Owner       = "DevOps"
  }
}

# ===============================================================================
# Lambda Function Configuration
# ===============================================================================

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions (-1 for unreserved)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 or a positive number."
  }
}

# ===============================================================================
# Step Functions Configuration
# ===============================================================================

variable "stepfunctions_type" {
  description = "Type of Step Functions state machine (STANDARD or EXPRESS)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.stepfunctions_type)
    error_message = "Step Functions type must be STANDARD or EXPRESS."
  }
}

variable "stepfunctions_logging_level" {
  description = "Logging level for Step Functions (OFF, ALL, ERROR, FATAL)"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["OFF", "ALL", "ERROR", "FATAL"], var.stepfunctions_logging_level)
    error_message = "Step Functions logging level must be OFF, ALL, ERROR, or FATAL."
  }
}

# ===============================================================================
# CloudWatch Logging Configuration
# ===============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "log_level" {
  description = "Log level for Lambda functions (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be DEBUG, INFO, WARNING, or ERROR."
  }
}

# ===============================================================================
# EventBridge Configuration
# ===============================================================================

variable "eventbridge_rule_state" {
  description = "State of the EventBridge rule (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.eventbridge_rule_state)
    error_message = "EventBridge rule state must be ENABLED or DISABLED."
  }
}

variable "eventbridge_rule_description" {
  description = "Description for the EventBridge rule"
  type        = string
  default     = "Trigger microservices workflow on order submission events"
}

# ===============================================================================
# Security Configuration
# ===============================================================================

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions and Step Functions"
  type        = bool
  default     = true
}

variable "lambda_vpc_config" {
  description = "VPC configuration for Lambda functions"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (optional)"
  type        = string
  default     = null
}

# ===============================================================================
# Performance and Scaling Configuration
# ===============================================================================

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda functions"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lambda_provisioned_concurrency >= 0
    error_message = "Provisioned concurrency must be 0 or a positive number."
  }
}

variable "lambda_dead_letter_config" {
  description = "Dead letter queue configuration for Lambda functions"
  type = object({
    target_arn = string
  })
  default = null
}

# ===============================================================================
# Monitoring and Alerting Configuration
# ===============================================================================

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email_endpoint" {
  description = "Email endpoint for CloudWatch alarm notifications"
  type        = string
  default     = null
}

variable "error_rate_threshold" {
  description = "Error rate threshold percentage for alarms"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100."
  }
}

variable "duration_threshold_ms" {
  description = "Duration threshold in milliseconds for performance alarms"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.duration_threshold_ms > 0
    error_message = "Duration threshold must be a positive number."
  }
}

# ===============================================================================
# Cost Optimization Configuration
# ===============================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for billing analysis"
  type        = bool
  default     = true
}

variable "lambda_architecture" {
  description = "Architecture for Lambda functions (x86_64 or arm64)"
  type        = string
  default     = "x86_64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be x86_64 or arm64."
  }
}

# ===============================================================================
# Development and Testing Configuration
# ===============================================================================

variable "enable_development_features" {
  description = "Enable additional features for development environments"
  type        = bool
  default     = false
}

variable "mock_external_services" {
  description = "Enable mocking of external services for testing"
  type        = bool
  default     = false
}

variable "lambda_layers" {
  description = "List of Lambda layer ARNs to attach to functions"
  type        = list(string)
  default     = []
}

# ===============================================================================
# Regional Configuration
# ===============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = null # Will use provider default
}

variable "availability_zones" {
  description = "List of availability zones for multi-AZ deployment"
  type        = list(string)
  default     = []
}