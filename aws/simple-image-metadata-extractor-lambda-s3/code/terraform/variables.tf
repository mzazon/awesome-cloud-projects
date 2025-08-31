# ============================================================================
# TERRAFORM VARIABLES FOR SIMPLE IMAGE METADATA EXTRACTOR
# ============================================================================
# This file defines all configurable variables for the image metadata
# extraction infrastructure. Variables are organized by service and include
# validation rules to ensure proper configuration.
# ============================================================================

# ============================================================================
# CORE CONFIGURATION VARIABLES
# ============================================================================

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "image-metadata-extractor"

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
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

# ============================================================================
# LAMBDA CONFIGURATION VARIABLES
# ============================================================================

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
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.12"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_architecture" {
  description = "Lambda function architecture (x86_64 for Intel/AMD, arm64 for Graviton)"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be either x86_64 or arm64."
  }
}

variable "lambda_log_level" {
  description = "Lambda function log level for CloudWatch"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.lambda_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for Lambda function"
  type        = map(string)
  default     = {}
}

variable "lambda_subnet_ids" {
  description = "List of subnet IDs for Lambda VPC configuration (optional)"
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "List of security group IDs for Lambda VPC configuration (optional)"
  type        = list(string)
  default     = []
}

# ============================================================================
# S3 CONFIGURATION VARIABLES
# ============================================================================

variable "s3_bucket_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects (useful for testing)"
  type        = bool
  default     = true
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning for data protection"
  type        = bool
  default     = true
}

variable "supported_image_formats" {
  description = "List of supported image file extensions that trigger processing"
  type        = list(string)
  default     = ["jpg", "jpeg", "png", "gif", "webp", "tiff", "bmp"]

  validation {
    condition     = length(var.supported_image_formats) > 0
    error_message = "At least one image format must be specified."
  }
}

variable "enable_lifecycle_policy" {
  description = "Enable S3 lifecycle policy for cost optimization"
  type        = bool
  default     = false
}

# ============================================================================
# CLOUDWATCH CONFIGURATION VARIABLES
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# ============================================================================
# SECURITY CONFIGURATION VARIABLES
# ============================================================================

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 bucket and CloudWatch logs"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda function performance monitoring"
  type        = bool
  default     = false
}

# ============================================================================
# MONITORING AND ALERTING VARIABLES
# ============================================================================

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for Lambda function monitoring"
  type        = bool
  default     = false
}

variable "sns_alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (optional)"
  type        = string
  default     = null
}

# ============================================================================
# ERROR HANDLING VARIABLES
# ============================================================================

variable "enable_dlq" {
  description = "Enable Dead Letter Queue for failed Lambda invocations"
  type        = bool
  default     = false
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for Dead Letter Queue in seconds"
  type        = number
  default     = 1209600  # 14 days

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "DLQ message retention must be between 60 seconds and 14 days."
  }
}

# ============================================================================
# RESOURCE NAMING VARIABLES
# ============================================================================

variable "use_random_suffix" {
  description = "Add random suffix to resource names for uniqueness (recommended for testing)"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6

  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 12
    error_message = "Random suffix length must be between 4 and 12 characters."
  }
}

# ============================================================================
# ADVANCED CONFIGURATION VARIABLES
# ============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency limit for Lambda function (optional)"
  type        = number
  default     = null

  validation {
    condition     = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Reserved concurrency must be between 0 and 1000, or null for no limit."
  }
}

variable "enable_provisioned_concurrency" {
  description = "Enable provisioned concurrency for Lambda function (reduces cold starts)"
  type        = bool
  default     = false
}

variable "provisioned_concurrency_amount" {
  description = "Amount of provisioned concurrency to configure"
  type        = number
  default     = 1

  validation {
    condition     = var.provisioned_concurrency_amount >= 1 && var.provisioned_concurrency_amount <= 1000
    error_message = "Provisioned concurrency must be between 1 and 1000."
  }
}

# ============================================================================
# PERFORMANCE TUNING VARIABLES
# ============================================================================

variable "lambda_ephemeral_storage_size" {
  description = "Lambda function ephemeral storage size in MB (for large image processing)"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_ephemeral_storage_size >= 512 && var.lambda_ephemeral_storage_size <= 10240
    error_message = "Ephemeral storage size must be between 512 and 10240 MB."
  }
}

variable "max_image_size_mb" {
  description = "Maximum allowed image size in MB for processing"
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_size_mb >= 1 && var.max_image_size_mb <= 100
    error_message = "Maximum image size must be between 1 and 100 MB."
  }
}

# ============================================================================
# COST OPTIMIZATION VARIABLES
# ============================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable detailed cost allocation tags for billing analysis"
  type        = bool
  default     = true
}

variable "s3_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for automatic cost optimization"
  type        = bool
  default     = false
}

# ============================================================================
# DEVELOPMENT AND TESTING VARIABLES
# ============================================================================

variable "enable_debug_logging" {
  description = "Enable debug logging for development and troubleshooting"
  type        = bool
  default     = false
}

variable "create_test_resources" {
  description = "Create additional resources for testing (test SNS topic, etc.)"
  type        = bool
  default     = false
}

# ============================================================================
# COMPLIANCE AND GOVERNANCE VARIABLES
# ============================================================================

variable "enforce_ssl_requests_only" {
  description = "Enforce SSL-only requests to S3 bucket"
  type        = bool
  default     = true
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for API call auditing"
  type        = bool
  default     = false
}

variable "data_classification" {
  description = "Data classification level for compliance (public, internal, confidential, restricted)"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, restricted."
  }
}