# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "intelligent-qa-system"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 Configuration
variable "documents_bucket_name" {
  description = "Name for the S3 bucket storing documents (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 bucket"
  type        = bool
  default     = true
}

# Kendra Configuration
variable "kendra_index_name" {
  description = "Name for the Kendra index"
  type        = string
  default     = "intelligent-qa-index"
}

variable "kendra_index_description" {
  description = "Description for the Kendra index"
  type        = string
  default     = "Intelligent document QA system powered by Kendra and Bedrock"
}

variable "kendra_index_edition" {
  description = "Kendra index edition (DEVELOPER_EDITION or ENTERPRISE_EDITION)"
  type        = string
  default     = "DEVELOPER_EDITION"

  validation {
    condition     = contains(["DEVELOPER_EDITION", "ENTERPRISE_EDITION"], var.kendra_index_edition)
    error_message = "Kendra index edition must be either DEVELOPER_EDITION or ENTERPRISE_EDITION."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = "qa-processor"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Bedrock Configuration
variable "bedrock_model_id" {
  description = "Bedrock model ID for text generation"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "bedrock_max_tokens" {
  description = "Maximum tokens for Bedrock model responses"
  type        = number
  default     = 1000

  validation {
    condition     = var.bedrock_max_tokens >= 1 && var.bedrock_max_tokens <= 4096
    error_message = "Bedrock max tokens must be between 1 and 4096."
  }
}

# API Gateway Configuration
variable "enable_api_gateway" {
  description = "Enable API Gateway for the QA system"
  type        = bool
  default     = true
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "v1"
}

variable "enable_api_key" {
  description = "Enable API key authentication for API Gateway"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

# Resource Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Security Configuration
variable "enable_s3_public_access_block" {
  description = "Enable S3 public access block"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for applicable resources"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (leave empty for AWS managed key)"
  type        = string
  default     = ""
}