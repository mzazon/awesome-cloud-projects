# Variables for AWS CLI Setup and First Commands Terraform Infrastructure
# These variables allow customization of the infrastructure for different environments and use cases

variable "bucket_prefix" {
  description = "Prefix for S3 bucket name to ensure uniqueness"
  type        = string
  default     = "aws-cli-tutorial"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must be between 3 and 63 characters, contain only lowercase letters, numbers, and hyphens, and not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod, tutorial)"
  type        = string
  default     = "tutorial"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,20}$", var.environment))
    error_message = "Environment must be alphanumeric with hyphens, maximum 20 characters."
  }
}

variable "iam_policy_prefix" {
  description = "Prefix for IAM policy names to avoid conflicts"
  type        = string
  default     = "cli-tutorial"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,50}$", var.iam_policy_prefix))
    error_message = "IAM policy prefix must be alphanumeric with hyphens, maximum 50 characters."
  }
}

variable "iam_role_prefix" {
  description = "Prefix for IAM role names to avoid conflicts"
  type        = string
  default     = "cli-tutorial"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,50}$", var.iam_role_prefix))
    error_message = "IAM role prefix must be alphanumeric with hyphens, maximum 50 characters."
  }
}

variable "create_ec2_role" {
  description = "Whether to create IAM role and instance profile for EC2-based CLI practice"
  type        = bool
  default     = false
}

variable "create_sample_objects" {
  description = "Whether to create sample objects in S3 bucket for CLI practice"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logging" {
  description = "Whether to create CloudWatch Log Group for monitoring CLI activities"
  type        = bool
  default     = false
}

variable "bucket_lifecycle_days" {
  description = "Number of days after which objects in the tutorial bucket will be deleted"
  type        = number
  default     = 7

  validation {
    condition     = var.bucket_lifecycle_days >= 1 && var.bucket_lifecycle_days <= 365
    error_message = "Bucket lifecycle days must be between 1 and 365."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653 days."
  }
}

variable "enable_s3_versioning" {
  description = "Whether to enable S3 bucket versioning for the tutorial bucket"
  type        = bool
  default     = true
}

variable "enable_bucket_encryption" {
  description = "Whether to enable server-side encryption for the S3 bucket"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either 'AES256' or 'aws:kms'."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (only used if encryption_algorithm is 'aws:kms')"
  type        = string
  default     = null
}

variable "enable_public_access_block" {
  description = "Whether to enable S3 public access block settings for security"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.tags) <= 10
    error_message = "Cannot specify more than 10 additional tags."
  }
}

variable "aws_region" {
  description = "AWS region for resources (if not specified, will use provider default)"
  type        = string
  default     = null

  validation {
    condition = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "bucket_force_destroy" {
  description = "Whether to force destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "create_sample_directories" {
  description = "Whether to create sample directory structure in S3 for CLI practice"
  type        = bool
  default     = true
}

variable "sample_file_content_type" {
  description = "Content type for sample files created in S3"
  type        = string
  default     = "text/plain"

  validation {
    condition     = can(regex("^[a-z]+/[a-z]+$", var.sample_file_content_type))
    error_message = "Content type must be in format 'type/subtype' (e.g., 'text/plain')."
  }
}

variable "enable_access_logging" {
  description = "Whether to enable S3 access logging for the tutorial bucket"
  type        = bool
  default     = false
}

variable "access_log_bucket_prefix" {
  description = "Prefix for S3 access log bucket (only used if enable_access_logging is true)"
  type        = string
  default     = "aws-cli-tutorial-access-logs"
}

variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = null

  validation {
    condition = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

variable "create_cli_user" {
  description = "Whether to create a dedicated IAM user for CLI tutorial practice"
  type        = bool
  default     = false
}

variable "cli_user_name" {
  description = "Name for the CLI tutorial IAM user (only used if create_cli_user is true)"
  type        = string
  default     = "aws-cli-tutorial-user"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.cli_user_name))
    error_message = "CLI user name must be 1-64 characters and contain only alphanumeric characters and +=,.@_- symbols."
  }
}