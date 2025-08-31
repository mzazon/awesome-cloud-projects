# =============================================================================
# Variables for Enterprise API Integration with AgentCore Gateway
# =============================================================================
# This file defines all configurable variables for the Terraform configuration
# that deploys the enterprise API integration system with comprehensive
# validation and documentation for each parameter.
# =============================================================================

# Core Configuration Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "api-integration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must only contain lowercase letters, numbers, and hyphens."
  }
  
  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 30
    error_message = "Project name must be between 3 and 30 characters long."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource tagging and configuration"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "development", "staging", "stage", "prod", "production", "test"], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Lambda Function Configuration
# =============================================================================

variable "lambda_runtime" {
  description = "Runtime version for Lambda functions (Python)"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12", "python3.13"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
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
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
  
  validation {
    condition     = var.lambda_memory_size % 64 == 0
    error_message = "Lambda memory size must be a multiple of 64 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency limit for Lambda functions (-1 for unreserved)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 (unreserved) or a positive number."
  }
}

# API Gateway Configuration
# =============================================================================

variable "api_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_stage_name))
    error_message = "API stage name must only contain alphanumeric characters, underscores, and hyphens."
  }
  
  validation {
    condition     = length(var.api_stage_name) >= 1 && length(var.api_stage_name) <= 64
    error_message = "API stage name must be between 1 and 64 characters long."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.api_throttle_burst_limit >= 0
    error_message = "API throttle burst limit must be a non-negative number."
  }
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.api_throttle_rate_limit >= 0
    error_message = "API throttle rate limit must be a non-negative number."
  }
}

# Step Functions Configuration
# =============================================================================

variable "stepfunctions_type" {
  description = "Type of Step Functions state machine (STANDARD or EXPRESS)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.stepfunctions_type)
    error_message = "Step Functions type must be either STANDARD or EXPRESS."
  }
}

variable "stepfunctions_logging_level" {
  description = "Logging level for Step Functions (ALL, ERROR, FATAL, OFF)"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.stepfunctions_logging_level)
    error_message = "Step Functions logging level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

# Monitoring and Observability Configuration
# =============================================================================

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions and Step Functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "log_level" {
  description = "Application log level for Lambda functions"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.log_level)
    error_message = "Log level must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for supported services"
  type        = bool
  default     = false
}

# Security Configuration
# =============================================================================

variable "enable_api_key_required" {
  description = "Require API key for API Gateway endpoints"
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "List of allowed CORS origins for API Gateway"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.allowed_origins) > 0
    error_message = "At least one allowed origin must be specified."
  }
}

variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway protection"
  type        = bool
  default     = false
}

# Cost Management Configuration
# =============================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for detailed billing tracking"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center identifier for billing and cost allocation"
  type        = string
  default     = ""
  
  validation {
    condition     = var.cost_center == "" || can(regex("^[a-zA-Z0-9-_]+$", var.cost_center))
    error_message = "Cost center must be empty or contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Enterprise Integration Configuration
# =============================================================================

variable "enterprise_systems" {
  description = "List of enterprise systems to integrate with"
  type = list(object({
    name        = string
    type        = string
    base_url    = string
    timeout     = number
    retries     = number
    description = string
  }))
  default = [
    {
      name        = "erp-system"
      type        = "erp"
      base_url    = "https://example-erp.com/api/v1"
      timeout     = 30
      retries     = 3
      description = "Enterprise Resource Planning System"
    },
    {
      name        = "crm-system"
      type        = "crm"
      base_url    = "https://example-crm.com/api/v2"
      timeout     = 20
      retries     = 2
      description = "Customer Relationship Management System"
    },
    {
      name        = "inventory-system"
      type        = "inventory"
      base_url    = "https://example-inventory.com/api/v1"
      timeout     = 15
      retries     = 2
      description = "Inventory Management System"
    }
  ]
  
  validation {
    condition = alltrue([
      for system in var.enterprise_systems : contains(["erp", "crm", "inventory"], system.type)
    ])
    error_message = "All enterprise system types must be one of: erp, crm, inventory."
  }
  
  validation {
    condition = alltrue([
      for system in var.enterprise_systems : system.timeout >= 5 && system.timeout <= 300
    ])
    error_message = "All enterprise system timeouts must be between 5 and 300 seconds."
  }
  
  validation {
    condition = alltrue([
      for system in var.enterprise_systems : system.retries >= 0 && system.retries <= 10
    ])
    error_message = "All enterprise system retry counts must be between 0 and 10."
  }
}

variable "validation_rules" {
  description = "Data validation rules configuration"
  type = object({
    financial = object({
      max_amount = number
      min_amount = number
      currency_codes = list(string)
    })
    customer = object({
      required_fields = list(string)
      email_validation = bool
      phone_validation = bool
    })
    standard = object({
      max_string_length = number
      required_fields = list(string)
    })
  })
  default = {
    financial = {
      max_amount     = 1000000
      min_amount     = 0
      currency_codes = ["USD", "EUR", "GBP", "JPY"]
    }
    customer = {
      required_fields  = ["id", "email"]
      email_validation = true
      phone_validation = true
    }
    standard = {
      max_string_length = 1000
      required_fields   = ["id", "type"]
    }
  }
}

# Performance Configuration
# =============================================================================

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda functions to reduce cold starts"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lambda_provisioned_concurrency >= 0
    error_message = "Provisioned concurrency must be a non-negative number."
  }
}

variable "stepfunctions_express_logging" {
  description = "Enable CloudWatch logging for Express Step Functions workflows"
  type        = bool
  default     = true
}

# Development and Testing Configuration
# =============================================================================

variable "enable_debug_mode" {
  description = "Enable debug mode with verbose logging and additional outputs"
  type        = bool
  default     = false
}

variable "create_test_resources" {
  description = "Create additional resources for testing and validation"
  type        = bool
  default     = false
}

variable "test_data_bucket" {
  description = "S3 bucket name for storing test data and configurations"
  type        = string
  default     = ""
  
  validation {
    condition = var.test_data_bucket == "" || (
      length(var.test_data_bucket) >= 3 && 
      length(var.test_data_bucket) <= 63 &&
      can(regex("^[a-z0-9.-]+$", var.test_data_bucket))
    )
    error_message = "Test data bucket name must be empty or a valid S3 bucket name (3-63 chars, lowercase, numbers, dots, hyphens)."
  }
}

# Advanced Configuration
# =============================================================================

variable "custom_domain_name" {
  description = "Custom domain name for API Gateway (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.custom_domain_name == "" || can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.custom_domain_name))
    error_message = "Custom domain name must be empty or a valid domain name."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom domain (required if custom_domain_name is set)"
  type        = string
  default     = ""
  
  validation {
    condition = var.certificate_arn == "" || can(regex("^arn:aws:acm:", var.certificate_arn))
    error_message = "Certificate ARN must be empty or a valid ACM certificate ARN."
  }
}

variable "vpc_config" {
  description = "VPC configuration for Lambda functions (optional)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = {
    subnet_ids         = []
    security_group_ids = []
  }
  
  validation {
    condition = (
      length(var.vpc_config.subnet_ids) == 0 && length(var.vpc_config.security_group_ids) == 0
    ) || (
      length(var.vpc_config.subnet_ids) > 0 && length(var.vpc_config.security_group_ids) > 0
    )
    error_message = "VPC configuration must be empty or include both subnet_ids and security_group_ids."
  }
}

variable "deadletter_queue_config" {
  description = "Dead letter queue configuration for failed processing"
  type = object({
    create_dlq           = bool
    max_receive_count    = number
    message_retention_days = number
  })
  default = {
    create_dlq           = true
    max_receive_count    = 3
    message_retention_days = 14
  }
  
  validation {
    condition     = var.deadletter_queue_config.max_receive_count >= 1 && var.deadletter_queue_config.max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
  
  validation {
    condition     = var.deadletter_queue_config.message_retention_days >= 1 && var.deadletter_queue_config.message_retention_days <= 14
    error_message = "Message retention days must be between 1 and 14."
  }
}

# Resource Tagging
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9+-=._:/@\\s]+$", key))
    ])
    error_message = "Tag keys must contain only valid characters."
  }
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : length(key) <= 128
    ])
    error_message = "Tag keys must be 128 characters or less."
  }
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : length(value) <= 256
    ])
    error_message = "Tag values must be 256 characters or less."
  }
}