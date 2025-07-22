# Variables for QLDB Infrastructure Configuration

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "ledger_name_prefix" {
  description = "Prefix for QLDB ledger name"
  type        = string
  default     = "financial-ledger"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.ledger_name_prefix))
    error_message = "Ledger name prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for QLDB ledger"
  type        = bool
  default     = true
}

variable "s3_bucket_name_prefix" {
  description = "Prefix for S3 bucket name for QLDB exports"
  type        = string
  default     = "qldb-exports"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.s3_bucket_name_prefix))
    error_message = "S3 bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kinesis_stream_name_prefix" {
  description = "Prefix for Kinesis stream name"
  type        = string
  default     = "qldb-journal-stream"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.kinesis_stream_name_prefix))
    error_message = "Kinesis stream name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
  
  validation {
    condition = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Kinesis shard count must be between 1 and 1000."
  }
}

variable "enable_kinesis_aggregation" {
  description = "Enable aggregation for Kinesis streaming"
  type        = bool
  default     = true
}

variable "s3_encryption_type" {
  description = "S3 encryption type for QLDB exports"
  type        = string
  default     = "SSE_S3"
  
  validation {
    condition = contains(["SSE_S3", "SSE_KMS"], var.s3_encryption_type)
    error_message = "S3 encryption type must be either SSE_S3 or SSE_KMS."
  }
}

variable "s3_export_prefix" {
  description = "Prefix for S3 journal exports"
  type        = string
  default     = "journal-exports/"
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "finance"
}

variable "owner" {
  description = "Owner for resource tagging"
  type        = string
  default     = "financial-team"
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Days after which to transition to Infrequent Access storage class"
  type        = number
  default     = 30
}

variable "s3_transition_to_glacier_days" {
  description = "Days after which to transition to Glacier storage class"
  type        = number
  default     = 90
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}