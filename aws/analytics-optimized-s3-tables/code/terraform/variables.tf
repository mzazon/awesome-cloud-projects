# Variables for S3 Tables Analytics Infrastructure
# This file defines all input variables for customizing the deployment

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "analytics-tables"
  
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
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "table_bucket_name" {
  description = "Name for the S3 table bucket (will be made unique with random suffix)"
  type        = string
  default     = "analytics-tables"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.table_bucket_name))
    error_message = "Table bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "namespace_name" {
  description = "Name for the table namespace"
  type        = string
  default     = "sales_analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.namespace_name))
    error_message = "Namespace name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "table_name" {
  description = "Name for the transaction data table"
  type        = string
  default     = "transaction_data"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.table_name))
    error_message = "Table name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_database_name" {
  description = "Name for the AWS Glue database"
  type        = string
  default     = "s3_tables_analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.glue_database_name))
    error_message = "Glue database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "enable_encryption" {
  description = "Enable KMS encryption for S3 Tables"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key (7-30)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "maintenance_enabled" {
  description = "Enable automatic maintenance for S3 Tables"
  type        = bool
  default     = true
}

variable "compaction_target_file_size_mb" {
  description = "Target file size in MB for table compaction (64-512)"
  type        = number
  default     = 128
  
  validation {
    condition     = var.compaction_target_file_size_mb >= 64 && var.compaction_target_file_size_mb <= 512
    error_message = "Compaction target file size must be between 64 and 512 MB."
  }
}

variable "max_snapshot_age_hours" {
  description = "Maximum age of snapshots in hours before deletion"
  type        = number
  default     = 168  # 7 days
  
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

variable "unreferenced_file_removal_days" {
  description = "Days after which unreferenced files are marked for deletion"
  type        = number
  default     = 3
  
  validation {
    condition     = var.unreferenced_file_removal_days >= 1
    error_message = "Unreferenced file removal days must be at least 1."
  }
}

variable "non_current_days" {
  description = "Days after which marked files are permanently deleted"
  type        = number
  default     = 1
  
  validation {
    condition     = var.non_current_days >= 1
    error_message = "Non-current days must be at least 1."
  }
}

variable "create_sample_data_bucket" {
  description = "Create S3 bucket for sample data storage"
  type        = bool
  default     = true
}

variable "enable_quicksight" {
  description = "Enable QuickSight data source configuration"
  type        = bool
  default     = false
}

variable "athena_query_result_bucket_force_destroy" {
  description = "Allow force destruction of Athena query results bucket"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}