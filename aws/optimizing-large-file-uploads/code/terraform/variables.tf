# Variables for S3 Multipart Upload Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 20
    error_message = "Environment must be between 1 and 20 characters."
  }
}

variable "bucket_prefix" {
  description = "Prefix for S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "multipart-upload-demo"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "lifecycle_incomplete_days" {
  description = "Number of days after which incomplete multipart uploads are deleted"
  type        = number
  default     = 7
  validation {
    condition     = var.lifecycle_incomplete_days >= 1 && var.lifecycle_incomplete_days <= 365
    error_message = "Lifecycle incomplete days must be between 1 and 365."
  }
}

variable "lifecycle_noncurrent_days" {
  description = "Number of days after which noncurrent versions are deleted"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_noncurrent_days >= 1 && var.lifecycle_noncurrent_days <= 365
    error_message = "Lifecycle noncurrent days must be between 1 and 365."
  }
}

variable "enable_transfer_acceleration" {
  description = "Enable S3 Transfer Acceleration for improved upload performance"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_metrics" {
  description = "Enable detailed CloudWatch metrics for S3 bucket"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "PUT", "POST", "DELETE", "HEAD"]
}

variable "bucket_public_access_block" {
  description = "Configuration for S3 bucket public access block"
  type = object({
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  default = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

variable "cloudwatch_dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = "S3-MultipartUpload-Monitoring"
  validation {
    condition = can(regex("^[a-zA-Z0-9_-]+$", var.cloudwatch_dashboard_name))
    error_message = "Dashboard name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "create_demo_lambda" {
  description = "Create a demo Lambda function for multipart upload operations"
  type        = bool
  default     = false
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([128, 256, 512, 1024, 2048, 3008], var.lambda_memory_size)
    error_message = "Lambda memory size must be one of: 128, 256, 512, 1024, 2048, 3008."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}