# Core configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

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
  default     = "cost-optimized-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 configuration variables
variable "bucket_name_suffix" {
  description = "Optional suffix for S3 bucket name (random suffix will be added automatically)"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete for S3 bucket (requires versioning)"
  type        = bool
  default     = false
}

# S3 Intelligent-Tiering configuration
variable "intelligent_tiering_prefix" {
  description = "S3 prefix for objects to include in Intelligent-Tiering"
  type        = string
  default     = "analytics-data/"
}

variable "archive_access_days" {
  description = "Days after which objects transition to Archive Access tier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.archive_access_days >= 90
    error_message = "Archive access days must be at least 90 days."
  }
}

variable "deep_archive_access_days" {
  description = "Days after which objects transition to Deep Archive Access tier"
  type        = number
  default     = 180
  
  validation {
    condition     = var.deep_archive_access_days >= 180
    error_message = "Deep archive access days must be at least 180 days."
  }
}

# Glue configuration variables
variable "glue_database_name" {
  description = "Name for AWS Glue database"
  type        = string
  default     = ""
}

variable "glue_table_name" {
  description = "Name for AWS Glue table"
  type        = string
  default     = "transaction_logs"
}

# Athena configuration variables
variable "athena_workgroup_name" {
  description = "Name for Athena workgroup"
  type        = string
  default     = ""
}

variable "athena_query_limit_bytes" {
  description = "Maximum bytes Athena can scan per query (prevents runaway costs)"
  type        = number
  default     = 1073741824  # 1 GB
  
  validation {
    condition     = var.athena_query_limit_bytes > 0
    error_message = "Athena query limit must be greater than 0."
  }
}

variable "athena_enforce_workgroup_config" {
  description = "Enforce workgroup configuration for all queries"
  type        = bool
  default     = true
}

# CloudWatch monitoring configuration
variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection for S3"
  type        = bool
  default     = true
}

variable "anomaly_detection_threshold" {
  description = "Cost anomaly detection threshold in USD"
  type        = number
  default     = 100
  
  validation {
    condition     = var.anomaly_detection_threshold > 0
    error_message = "Anomaly detection threshold must be greater than 0."
  }
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}