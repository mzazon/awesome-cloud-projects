variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "notification_email" {
  description = "Email address for content moderation notifications"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-moderation"
}

variable "content_bucket_name" {
  description = "Name of the S3 bucket for content uploads (optional - will be generated if not provided)"
  type        = string
  default     = ""
}

variable "approved_bucket_name" {
  description = "Name of the S3 bucket for approved content (optional - will be generated if not provided)"
  type        = string
  default     = ""
}

variable "rejected_bucket_name" {
  description = "Name of the S3 bucket for rejected content (optional - will be generated if not provided)"
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for content analysis"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
}

variable "content_analysis_memory_size" {
  description = "Memory size for content analysis Lambda function in MB"
  type        = number
  default     = 512
}

variable "workflow_memory_size" {
  description = "Memory size for workflow Lambda functions in MB"
  type        = number
  default     = 256
}

variable "enable_guardrails" {
  description = "Enable Bedrock Guardrails for enhanced content filtering"
  type        = bool
  default     = true
}

variable "guardrail_filters" {
  description = "Configuration for Bedrock Guardrail content filters"
  type = object({
    sexual_filter_strength     = string
    violence_filter_strength   = string
    hate_filter_strength       = string
    insults_filter_strength    = string
    misconduct_filter_strength = string
  })
  default = {
    sexual_filter_strength     = "HIGH"
    violence_filter_strength   = "HIGH"
    hate_filter_strength       = "HIGH"
    insults_filter_strength    = "MEDIUM"
    misconduct_filter_strength = "HIGH"
  }
}

variable "s3_object_expiration_days" {
  description = "Number of days after which S3 objects expire (0 to disable)"
  type        = number
  default     = 90
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}