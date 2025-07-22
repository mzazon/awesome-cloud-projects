# Variables for IoT firmware updates infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
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
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "iot-firmware-updates"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "firmware_bucket_name" {
  description = "Name for the S3 bucket storing firmware files (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "thing_name" {
  description = "Name for the IoT Thing (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "thing_group_name" {
  description = "Name for the IoT Thing Group (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "signing_platform_id" {
  description = "AWS Signer platform ID for firmware signing"
  type        = string
  default     = "AmazonFreeRTOS-TI-CC3220SF"

  validation {
    condition = contains([
      "AmazonFreeRTOS-TI-CC3220SF",
      "AmazonFreeRTOS-Default",
      "AWSLambda-SHA384-ECDSA"
    ], var.signing_platform_id)
    error_message = "Signing platform ID must be a valid AWS Signer platform."
  }
}

variable "signature_validity_days" {
  description = "Number of days the signature remains valid"
  type        = number
  default     = 365

  validation {
    condition     = var.signature_validity_days > 0 && var.signature_validity_days <= 3650
    error_message = "Signature validity must be between 1 and 3650 days."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300

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

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "s3_kms_key_id" {
  description = "KMS key ID for S3 encryption (only used if encryption_algorithm is aws:kms)"
  type        = string
  default     = null
}

variable "job_rollout_max_per_minute" {
  description = "Maximum number of devices to update per minute"
  type        = number
  default     = 10

  validation {
    condition     = var.job_rollout_max_per_minute > 0 && var.job_rollout_max_per_minute <= 1000
    error_message = "Job rollout max per minute must be between 1 and 1000."
  }
}

variable "job_rollout_base_rate_per_minute" {
  description = "Base rate for exponential rollout"
  type        = number
  default     = 5

  validation {
    condition     = var.job_rollout_base_rate_per_minute > 0 && var.job_rollout_base_rate_per_minute <= 1000
    error_message = "Job rollout base rate per minute must be between 1 and 1000."
  }
}

variable "job_rollout_increment_factor" {
  description = "Increment factor for exponential rollout"
  type        = number
  default     = 2.0

  validation {
    condition     = var.job_rollout_increment_factor >= 1.0 && var.job_rollout_increment_factor <= 5.0
    error_message = "Job rollout increment factor must be between 1.0 and 5.0."
  }
}

variable "job_abort_failure_threshold" {
  description = "Percentage of failed jobs that triggers abort"
  type        = number
  default     = 20.0

  validation {
    condition     = var.job_abort_failure_threshold > 0 && var.job_abort_failure_threshold <= 100
    error_message = "Job abort failure threshold must be between 0 and 100."
  }
}

variable "job_timeout_minutes" {
  description = "Timeout for job execution in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.job_timeout_minutes > 0 && var.job_timeout_minutes <= 10080
    error_message = "Job timeout must be between 1 and 10080 minutes (1 week)."
  }
}

variable "create_sample_device" {
  description = "Whether to create a sample IoT device for testing"
  type        = bool
  default     = true
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}