# AWS Region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Environment identifier
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) > 0
    error_message = "Environment must be a non-empty string."
  }
}

# Project name
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "data-quality-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 bucket name prefix
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "databrew-results"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Email for SNS notifications
variable "notification_email" {
  description = "Email address for data quality notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

# DataBrew dataset configuration
variable "dataset_name" {
  description = "Name of the DataBrew dataset"
  type        = string
  default     = "customer-data"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.dataset_name))
    error_message = "Dataset name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# DataBrew profile job configuration
variable "profile_job_name" {
  description = "Name of the DataBrew profile job"
  type        = string
  default     = "customer-profile-job"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.profile_job_name))
    error_message = "Profile job name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# DataBrew ruleset configuration
variable "ruleset_name" {
  description = "Name of the DataBrew data quality ruleset"
  type        = string
  default     = "customer-quality-rules"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.ruleset_name))
    error_message = "Ruleset name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Sample data configuration
variable "create_sample_data" {
  description = "Whether to create sample customer data for testing"
  type        = bool
  default     = true
}

# Data format configuration
variable "data_format" {
  description = "Format of the input data"
  type        = string
  default     = "CSV"
  
  validation {
    condition     = contains(["CSV", "JSON", "PARQUET", "EXCEL"], var.data_format)
    error_message = "Data format must be one of: CSV, JSON, PARQUET, EXCEL."
  }
}

# CSV delimiter configuration
variable "csv_delimiter" {
  description = "Delimiter for CSV files"
  type        = string
  default     = ","
  
  validation {
    condition     = contains([",", ";", "|", "\t"], var.csv_delimiter)
    error_message = "CSV delimiter must be one of: , ; | or tab."
  }
}

# Profile job configuration
variable "profile_job_configuration" {
  description = "Configuration for the DataBrew profile job"
  type = object({
    max_capacity          = number
    max_retries          = number
    timeout              = number
    job_sample_size      = number
    include_all_stats    = bool
  })
  default = {
    max_capacity          = 10
    max_retries          = 3
    timeout              = 2880  # 48 hours in minutes
    job_sample_size      = 5000
    include_all_stats    = true
  }
}

# Data quality rules configuration
variable "data_quality_rules" {
  description = "Data quality rules for validation"
  type = list(object({
    name              = string
    check_expression  = string
    threshold         = number
    disabled          = bool
    description       = string
  }))
  default = [
    {
      name              = "customer_id_completeness"
      check_expression  = "COLUMN_COMPLETENESS(customer_id) > 0.95"
      threshold         = 0.95
      disabled          = false
      description       = "Customer ID should be complete for 95% of records"
    },
    {
      name              = "email_format_validation"
      check_expression  = "COLUMN_MATCHES_REGEX(email, \"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$\") > 0.8"
      threshold         = 0.8
      disabled          = false
      description       = "Email format should be valid for 80% of records"
    },
    {
      name              = "age_range_validation"
      check_expression  = "COLUMN_MIN(age) >= 0 AND COLUMN_MAX(age) <= 120"
      threshold         = 1.0
      disabled          = false
      description       = "Age should be between 0 and 120 years"
    },
    {
      name              = "account_balance_positive"
      check_expression  = "COLUMN_MIN(account_balance) >= 0"
      threshold         = 1.0
      disabled          = false
      description       = "Account balance should be non-negative"
    },
    {
      name              = "registration_date_format"
      check_expression  = "COLUMN_DATA_TYPE(registration_date) = DATE"
      threshold         = 1.0
      disabled          = false
      description       = "Registration date should be in valid date format"
    }
  ]
}

# EventBridge rule configuration
variable "eventbridge_rule_config" {
  description = "Configuration for EventBridge rule"
  type = object({
    enabled               = bool
    description          = string
    event_bus_name       = string
    failure_notifications = bool
    success_notifications = bool
  })
  default = {
    enabled               = true
    description          = "Monitor DataBrew data quality validation results"
    event_bus_name       = "default"
    failure_notifications = true
    success_notifications = false
  }
}

# CloudWatch log retention
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

# Default tags
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DataQualityMonitoring"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "DataBrew Data Quality Monitoring"
  }
}