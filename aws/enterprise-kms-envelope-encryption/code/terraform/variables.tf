# ======================================
# Variables for Enterprise KMS Envelope Encryption
# ======================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "enterprise-encryption"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kms_key_description" {
  description = "Description for the KMS customer master key"
  type        = string
  default     = "Enterprise envelope encryption master key with automated rotation"
}

variable "enable_key_rotation" {
  description = "Enable automatic key rotation for the KMS key"
  type        = bool
  default     = true
}

variable "s3_bucket_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_force_destroy" {
  description = "Allow force destruction of S3 bucket with objects (USE WITH CAUTION)"
  type        = bool
  default     = false
}

variable "lambda_runtime" {
  description = "Lambda function runtime version"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "monitoring_schedule" {
  description = "CloudWatch Events schedule expression for key rotation monitoring"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition     = can(regex("^(rate|cron)\\(.+\\)$", var.monitoring_schedule))
    error_message = "Schedule must be a valid CloudWatch Events schedule expression."
  }
}

variable "enable_s3_bucket_key" {
  description = "Enable S3 bucket key for KMS cost optimization"
  type        = bool
  default     = true
}

variable "kms_key_policy_additional_principals" {
  description = "Additional AWS principals to grant access to the KMS key"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for principal in var.kms_key_policy_additional_principals :
      can(regex("^arn:aws:(iam|sts)::", principal))
    ])
    error_message = "All principals must be valid AWS ARNs."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}