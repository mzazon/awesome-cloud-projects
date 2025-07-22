# Core configuration variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "multitenant-saas"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Cognito configuration
variable "cognito_domain_prefix" {
  description = "Prefix for Cognito hosted UI domain"
  type        = string
  default     = null
}

variable "cognito_callback_urls" {
  description = "List of callback URLs for Cognito"
  type        = list(string)
  default     = ["http://localhost:3000/auth/callback"]
}

variable "cognito_logout_urls" {
  description = "List of logout URLs for Cognito"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

# DynamoDB configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "enable_dynamodb_encryption" {
  description = "Enable encryption at rest for DynamoDB tables"
  type        = bool
  default     = true
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"

  validation {
    condition     = contains(["nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# AppSync configuration
variable "appsync_authentication_type" {
  description = "Primary authentication type for AppSync API"
  type        = string
  default     = "AMAZON_COGNITO_USER_POOLS"

  validation {
    condition = contains([
      "AMAZON_COGNITO_USER_POOLS",
      "AWS_IAM",
      "OPENID_CONNECT",
      "AWS_LAMBDA"
    ], var.appsync_authentication_type)
    error_message = "Authentication type must be a valid AppSync authentication type."
  }
}

variable "enable_appsync_logging" {
  description = "Enable CloudWatch logging for AppSync"
  type        = bool
  default     = true
}

variable "appsync_log_level" {
  description = "Log level for AppSync CloudWatch logs"
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["NONE", "ERROR", "ALL"], var.appsync_log_level)
    error_message = "Log level must be one of: NONE, ERROR, ALL."
  }
}

# S3 configuration
variable "enable_s3_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning S3 objects to IA storage"
  type        = number
  default     = 30
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring S3 objects"
  type        = number
  default     = 365
}

# CloudWatch configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
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

# Tenant configuration
variable "default_tenant_settings" {
  description = "Default settings for new tenants"
  type = object({
    max_users_trial        = number
    max_users_basic        = number
    max_users_professional = number
    max_users_enterprise   = number
    max_projects_trial     = number
    max_projects_basic     = number
    max_projects_professional = number
    max_projects_enterprise   = number
    max_storage_gb_trial      = number
    max_storage_gb_basic      = number
    max_storage_gb_professional = number
    max_storage_gb_enterprise   = number
    api_rate_limit_trial        = number
    api_rate_limit_basic        = number
    api_rate_limit_professional = number
    api_rate_limit_enterprise   = number
  })
  default = {
    max_users_trial        = 5
    max_users_basic        = 25
    max_users_professional = 100
    max_users_enterprise   = 1000
    max_projects_trial     = 3
    max_projects_basic     = 10
    max_projects_professional = 50
    max_projects_enterprise   = 500
    max_storage_gb_trial      = 1
    max_storage_gb_basic      = 5
    max_storage_gb_professional = 25
    max_storage_gb_enterprise   = 100
    api_rate_limit_trial        = 100
    api_rate_limit_basic        = 500
    api_rate_limit_professional = 2000
    api_rate_limit_enterprise   = 10000
  }
}

# Monitoring configuration
variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions and AppSync"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring with custom metrics"
  type        = bool
  default     = false
}

# Cost optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}