# ==============================================================================
# Variables for Analytics-Ready Data Storage with S3 Tables
# ==============================================================================

# ==============================================================================
# General Configuration
# ==============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "analytics-ready-data-storage"
    Environment = "development"
    ManagedBy   = "terraform"
    Recipe      = "s3-tables-analytics"
  }
}

# ==============================================================================
# S3 Tables Configuration
# ==============================================================================

variable "table_bucket_prefix" {
  description = "Prefix for the S3 table bucket name (will be suffixed with random string)"
  type        = string
  default     = "analytics-data"

  validation {
    condition = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.table_bucket_prefix)) && length(var.table_bucket_prefix) >= 3 && length(var.table_bucket_prefix) <= 50
    error_message = "Table bucket prefix must be between 3-50 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace_name" {
  description = "Name of the S3 Tables namespace for logical organization"
  type        = string
  default     = "analytics_data"

  validation {
    condition = can(regex("^[a-z0-9][a-z0-9_]*[a-z0-9]$", var.namespace_name)) && length(var.namespace_name) >= 1 && length(var.namespace_name) <= 255
    error_message = "Namespace name must be 1-255 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, and underscores."
  }
}

variable "sample_table_name" {
  description = "Name of the sample customer events table"
  type        = string
  default     = "customer_events"

  validation {
    condition = can(regex("^[a-z0-9][a-z0-9_]*[a-z0-9]$", var.sample_table_name)) && length(var.sample_table_name) >= 1 && length(var.sample_table_name) <= 255
    error_message = "Table name must be 1-255 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, and underscores."
  }
}

# ==============================================================================
# S3 Tables Maintenance Configuration
# ==============================================================================

variable "unreferenced_file_cleanup_days" {
  description = "Number of days after which unreferenced files are marked for deletion"
  type        = number
  default     = 7

  validation {
    condition     = var.unreferenced_file_cleanup_days >= 1
    error_message = "Unreferenced file cleanup days must be at least 1."
  }
}

variable "non_current_file_cleanup_days" {
  description = "Number of days after which non-current files are deleted"
  type        = number
  default     = 3

  validation {
    condition     = var.non_current_file_cleanup_days >= 1
    error_message = "Non-current file cleanup days must be at least 1."
  }
}

variable "target_file_size_mb" {
  description = "Target file size in MB for automatic compaction (64-512 MB)"
  type        = number
  default     = 128

  validation {
    condition     = var.target_file_size_mb >= 64 && var.target_file_size_mb <= 512
    error_message = "Target file size must be between 64 and 512 MB."
  }
}

variable "max_snapshot_age_hours" {
  description = "Maximum age in hours for table snapshots before deletion"
  type        = number
  default     = 168 # 7 days

  validation {
    condition     = var.max_snapshot_age_hours >= 1
    error_message = "Maximum snapshot age must be at least 1 hour."
  }
}

variable "min_snapshots_to_keep" {
  description = "Minimum number of snapshots to retain"
  type        = number
  default     = 5

  validation {
    condition     = var.min_snapshots_to_keep >= 1
    error_message = "Minimum snapshots to keep must be at least 1."
  }
}

# ==============================================================================
# Analytics Services Configuration
# ==============================================================================

variable "additional_analytics_services" {
  description = "Additional AWS analytics services to grant S3 Tables access (e.g., redshift.amazonaws.com, emr.amazonaws.com)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for service in var.additional_analytics_services :
      can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", service))
    ])
    error_message = "Each service must be a valid AWS service principal (e.g., redshift.amazonaws.com)."
  }
}

# ==============================================================================
# Amazon Athena Configuration
# ==============================================================================

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup for S3 Tables queries"
  type        = string
  default     = "s3-tables-workgroup"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.athena_workgroup_name))
    error_message = "Athena workgroup name can contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "athena_bytes_scanned_cutoff" {
  description = "Maximum bytes a single query can scan (minimum 10 MB)"
  type        = number
  default     = 1073741824 # 1 GB

  validation {
    condition     = var.athena_bytes_scanned_cutoff >= 10485760
    error_message = "Athena bytes scanned cutoff must be at least 10,485,760 bytes (10 MB)."
  }
}

# ==============================================================================
# AWS Glue Configuration
# ==============================================================================

variable "glue_database_name" {
  description = "Name of the AWS Glue database for S3 Tables integration"
  type        = string
  default     = "s3_tables_analytics"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.glue_database_name)) && length(var.glue_database_name) >= 1 && length(var.glue_database_name) <= 255
    error_message = "Glue database name must be 1-255 characters and contain only lowercase letters, numbers, and underscores."
  }
}

# ==============================================================================
# Environment and Region Configuration
# ==============================================================================

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources in production"
  type        = bool
  default     = false
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery features where applicable"
  type        = bool
  default     = false
}

# ==============================================================================
# Cost Optimization Configuration
# ==============================================================================

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "lifecycle_transition_days" {
  description = "Number of days before transitioning objects to cheaper storage classes"
  type        = number
  default     = 30

  validation {
    condition     = var.lifecycle_transition_days >= 1
    error_message = "Lifecycle transition days must be at least 1."
  }
}

# ==============================================================================
# Security Configuration
# ==============================================================================

variable "enable_s3_bucket_logging" {
  description = "Enable access logging for S3 buckets"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption (if not provided, AWS managed keys will be used)"
  type        = string
  default     = ""

  validation {
    condition = var.kms_key_arn == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "KMS key ARN must be a valid AWS KMS key ARN or empty string."
  }
}

variable "allowed_source_ips" {
  description = "List of IP addresses or CIDR blocks allowed to access resources"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allowed_source_ips :
      can(cidrhost(ip, 0)) || can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", ip))
    ])
    error_message = "Each IP must be a valid IP address or CIDR block."
  }
}