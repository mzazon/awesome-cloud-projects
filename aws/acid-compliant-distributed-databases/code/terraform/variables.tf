# ============================================================================
# Required Variables
# ============================================================================

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev, test)"
  type        = string
  
  validation {
    condition = can(regex("^(prod|staging|dev|test)$", var.environment))
    error_message = "Environment must be one of: prod, staging, dev, test."
  }
}

variable "application_name" {
  description = "Application name used for resource naming and tagging"
  type        = string
  default     = "financial-ledger"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name)) && length(var.application_name) <= 32
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens, and be 32 characters or less."
  }
}

# ============================================================================
# QLDB Configuration Variables
# ============================================================================

variable "deletion_protection" {
  description = "Enable deletion protection for QLDB ledger (recommended for production)"
  type        = bool
  default     = true
}

variable "stream_start_time" {
  description = "Inclusive start time for journal streaming (RFC 3339 format)"
  type        = string
  default     = null
  
  validation {
    condition = var.stream_start_time == null || can(formatdate("RFC3339", var.stream_start_time))
    error_message = "Stream start time must be in RFC 3339 format (e.g., '2024-01-01T00:00:00Z') or null."
  }
}

# ============================================================================
# S3 Configuration Variables
# ============================================================================

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning for audit trail protection"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket with objects (use with caution)"
  type        = bool
  default     = false
}

# ============================================================================
# Kinesis Configuration Variables
# ============================================================================

variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Kinesis shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_hours" {
  description = "Data retention period for Kinesis stream in hours (24-8760)"
  type        = number
  default     = 168 # 7 days
  
  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "Kinesis retention period must be between 24 hours (1 day) and 8760 hours (365 days)."
  }
}

# ============================================================================
# Monitoring and Alerting Variables
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 90
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the allowed CloudWatch retention periods."
  }
}

variable "read_io_alarm_threshold" {
  description = "Threshold for QLDB read I/O CloudWatch alarm"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.read_io_alarm_threshold > 0
    error_message = "Read I/O alarm threshold must be greater than 0."
  }
}

variable "write_io_alarm_threshold" {
  description = "Threshold for QLDB write I/O CloudWatch alarm"
  type        = number
  default     = 500
  
  validation {
    condition     = var.write_io_alarm_threshold > 0
    error_message = "Write I/O alarm threshold must be greater than 0."
  }
}

variable "alarm_notification_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (leave empty to disable notifications)"
  type        = string
  default     = ""
  
  validation {
    condition = var.alarm_notification_arn == "" || can(regex("^arn:aws:sns:", var.alarm_notification_arn))
    error_message = "Alarm notification ARN must be a valid SNS topic ARN or empty string."
  }
}

# ============================================================================
# Tagging Variables
# ============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = length(var.tags) <= 50
    error_message = "Maximum of 50 additional tags are allowed."
  }
}

# ============================================================================
# Network Configuration Variables (for future expansion)
# ============================================================================

variable "vpc_id" {
  description = "VPC ID for resources that support VPC endpoints (optional for future expansion)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vpc_id == "" || can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid VPC identifier (vpc-xxxxxxxx) or empty string."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC endpoints (optional for future expansion)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([for subnet in var.subnet_ids : can(regex("^subnet-[a-z0-9]+$", subnet))])
    error_message = "All subnet IDs must be valid subnet identifiers (subnet-xxxxxxxx)."
  }
}

# ============================================================================
# Cost Optimization Variables
# ============================================================================

variable "enable_s3_lifecycle" {
  description = "Enable S3 lifecycle management for cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days before transitioning S3 objects to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_to_ia_days >= 30
    error_message = "S3 transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days before transitioning S3 objects to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_transition_to_glacier_days >= 30
    error_message = "S3 transition to Glacier must be at least 30 days."
  }
}

variable "s3_transition_to_deep_archive_days" {
  description = "Number of days before transitioning S3 objects to Deep Archive"
  type        = number
  default     = 365
  
  validation {
    condition     = var.s3_transition_to_deep_archive_days >= 90
    error_message = "S3 transition to Deep Archive must be at least 90 days."
  }
}

variable "s3_expiration_days" {
  description = "Number of days before S3 objects expire (for regulatory compliance, typically 7 years = 2555 days)"
  type        = number
  default     = 2555 # 7 years for financial compliance
  
  validation {
    condition     = var.s3_expiration_days >= 365
    error_message = "S3 expiration must be at least 365 days for compliance requirements."
  }
}

# ============================================================================
# Security Variables
# ============================================================================

variable "kms_key_id" {
  description = "KMS key ID for encryption (uses AWS managed keys if not specified)"
  type        = string
  default     = ""
  
  validation {
    condition = var.kms_key_id == "" || can(regex("^(arn:aws:kms:|alias/)", var.kms_key_id))
    error_message = "KMS key ID must be a valid key ARN, alias, or empty string."
  }
}

variable "enable_access_logging" {
  description = "Enable S3 access logging for audit purposes"
  type        = bool
  default     = false
}

variable "access_log_bucket" {
  description = "S3 bucket for access logs (required if enable_access_logging is true)"
  type        = string
  default     = ""
  
  validation {
    condition = !var.enable_access_logging || (var.enable_access_logging && var.access_log_bucket != "")
    error_message = "Access log bucket must be specified when access logging is enabled."
  }
}