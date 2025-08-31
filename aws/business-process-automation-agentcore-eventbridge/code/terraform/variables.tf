# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "biz-automation"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# Bedrock Agent Configuration
variable "bedrock_model_id" {
  description = "Bedrock foundation model ID for the agent"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+:[0-9]+:[0-9]+$", var.bedrock_model_id))
    error_message = "Bedrock model ID must be in valid format (e.g., anthropic.claude-3-sonnet-20240229-v1:0)."
  }
}

variable "agent_instruction" {
  description = "Instructions for the Bedrock agent"
  type        = string
  default     = "You are a business process automation agent. Analyze documents uploaded to S3, extract key information, make recommendations for approval or processing, and trigger appropriate business workflows through EventBridge events. Focus on accuracy, compliance, and efficient processing."
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management for cost optimization"
  type        = bool
  default     = true
}

variable "s3_intelligent_tiering_enabled" {
  description = "Enable S3 Intelligent Tiering for automatic cost optimization"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# EventBridge Configuration
variable "event_bus_kms_key_id" {
  description = "KMS key ID for EventBridge encryption (optional)"
  type        = string
  default     = null
}

# Monitoring and Logging
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2557, 2922, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_bucket_public_access_block" {
  description = "Enable S3 bucket public access block"
  type        = bool
  default     = true
}

variable "enable_bucket_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 10
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Resource Naming
variable "resource_name_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}