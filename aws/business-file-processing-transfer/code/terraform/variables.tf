# Variable definitions for AWS Transfer Family and Step Functions file processing infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "file-processing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning for data protection"
  type        = bool
  default     = true
}

variable "s3_bucket_force_destroy" {
  description = "Allow Terraform to destroy S3 buckets even if they contain objects (use with caution)"
  type        = bool
  default     = false
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "transfer_family_endpoint_type" {
  description = "Transfer Family endpoint type (PUBLIC or VPC)"
  type        = string
  default     = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "VPC"], var.transfer_family_endpoint_type)
    error_message = "Transfer Family endpoint type must be either PUBLIC or VPC."
  }
}

variable "sftp_username" {
  description = "Username for SFTP access"
  type        = string
  default     = "businesspartner"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.sftp_username))
    error_message = "SFTP username must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be one of the allowed values."
  }
}

variable "step_functions_log_level" {
  description = "Step Functions execution logging level"
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions and Step Functions"
  type        = bool
  default     = true
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

variable "enable_encryption" {
  description = "Enable encryption for S3 buckets and other resources"
  type        = bool
  default     = true
}