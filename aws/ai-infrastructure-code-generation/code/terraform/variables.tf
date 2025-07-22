# Variable Definitions for AI-Powered Infrastructure Code Generation
# This file defines all input variables for the Terraform configuration

# Application configuration variables
variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "q-developer-automation"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.application_name))
    error_message = "Application name must start with a letter and contain only alphanumeric characters and hyphens."
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

# S3 configuration variables
variable "enable_s3_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_days" {
  description = "Number of days after which objects transition to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_days >= 1
    error_message = "Lifecycle days must be at least 1."
  }
}

# Lambda configuration variables
variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# CloudWatch configuration variables
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Auto-deployment configuration
variable "enable_auto_deployment" {
  description = "Enable automatic CloudFormation stack deployment for templates in auto-deploy prefix"
  type        = bool
  default     = false
}

variable "auto_deploy_prefix" {
  description = "S3 prefix for templates that should be automatically deployed"
  type        = string
  default     = "auto-deploy/"
}

# Notification configuration
variable "enable_sns_notifications" {
  description = "Enable SNS notifications for template processing results"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for notifications (required if SNS notifications enabled)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_sns_notifications == false || (
      var.enable_sns_notifications == true && can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    )
    error_message = "A valid email address is required when SNS notifications are enabled."
  }
}

# Security configuration
variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "S3 encryption algorithm"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for S3 encryption (required if encryption algorithm is aws:kms)"
  type        = string
  default     = ""
}

# Network configuration (if Lambda needs VPC access)
variable "enable_vpc_config" {
  description = "Enable VPC configuration for Lambda function"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

# Tagging variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# CloudFormation stack configuration
variable "cloudformation_stack_policy" {
  description = "CloudFormation stack policy for auto-deployed stacks"
  type        = string
  default     = ""
}

variable "cloudformation_capabilities" {
  description = "CloudFormation capabilities for auto-deployed stacks"
  type        = list(string)
  default     = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]
}