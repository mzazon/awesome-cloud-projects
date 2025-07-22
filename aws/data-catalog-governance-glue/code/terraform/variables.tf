# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "data-governance"
}

# Data Catalog Configuration
variable "database_name" {
  description = "Name of the Glue Data Catalog database"
  type        = string
  default     = null
}

variable "database_description" {
  description = "Description for the Glue Data Catalog database"
  type        = string
  default     = "Data governance catalog database"
}

variable "crawler_name" {
  description = "Name of the Glue crawler"
  type        = string
  default     = null
}

variable "crawler_schedule" {
  description = "Schedule for the Glue crawler (cron expression)"
  type        = string
  default     = null
}

variable "classifier_name" {
  description = "Name of the PII classifier"
  type        = string
  default     = null
}

# S3 Configuration
variable "create_sample_data" {
  description = "Whether to create sample data for testing"
  type        = bool
  default     = true
}

variable "existing_data_bucket" {
  description = "Existing S3 bucket with data (if not creating sample data)"
  type        = string
  default     = null
}

variable "existing_data_prefix" {
  description = "S3 prefix for existing data"
  type        = string
  default     = "data/"
}

# Lake Formation Configuration
variable "enable_lake_formation" {
  description = "Whether to enable Lake Formation governance"
  type        = bool
  default     = true
}

variable "lake_formation_admins" {
  description = "List of Lake Formation administrators (ARNs)"
  type        = list(string)
  default     = []
}

# CloudTrail Configuration
variable "enable_cloudtrail" {
  description = "Whether to enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_name" {
  description = "Name of the CloudTrail"
  type        = string
  default     = null
}

variable "include_global_service_events" {
  description = "Whether to include global service events in CloudTrail"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Whether CloudTrail should be multi-region"
  type        = bool
  default     = true
}

variable "enable_log_file_validation" {
  description = "Whether to enable CloudTrail log file validation"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
  default     = null
}

# PII Detection Configuration
variable "pii_detection_threshold" {
  description = "Threshold for PII detection (0.0 to 1.0)"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.pii_detection_threshold >= 0.0 && var.pii_detection_threshold <= 1.0
    error_message = "PII detection threshold must be between 0.0 and 1.0."
  }
}

variable "pii_sample_fraction" {
  description = "Fraction of data to sample for PII detection"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.pii_sample_fraction >= 0.0 && var.pii_sample_fraction <= 1.0
    error_message = "PII sample fraction must be between 0.0 and 1.0."
  }
}

# Access Control Configuration
variable "create_data_analyst_role" {
  description = "Whether to create a data analyst IAM role"
  type        = bool
  default     = true
}

variable "data_analyst_role_name" {
  description = "Name of the data analyst IAM role"
  type        = string
  default     = null
}

variable "additional_iam_policies" {
  description = "Additional IAM policy ARNs to attach to the Glue service role"
  type        = list(string)
  default     = []
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}