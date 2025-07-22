# Variables for AWS Glue Data Lake Ingestion Pipeline
# These variables allow customization of the infrastructure deployment

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "data-lake-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = null
}

variable "s3_bucket_name" {
  description = "Name for the S3 data lake bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.s3_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.s3_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "glue_database_name" {
  description = "Name for the AWS Glue database"
  type        = string
  default     = ""
  
  validation {
    condition     = var.glue_database_name == "" || can(regex("^[a-zA-Z0-9_-]+$", var.glue_database_name))
    error_message = "Glue database name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "crawler_schedule" {
  description = "Cron expression for crawler schedule (empty string disables scheduling)"
  type        = string
  default     = "cron(0 6 * * ? *)"
  
  validation {
    condition     = var.crawler_schedule == "" || can(regex("^cron\\([0-9*/?,-]+\\s+[0-9*/?,-]+\\s+[0-9*/?,-]+\\s+[0-9*/?,-]+\\s+[0-9*/?,-L]+\\s*[0-9*/?,-]*\\)$", var.crawler_schedule))
    error_message = "Crawler schedule must be a valid cron expression or empty string."
  }
}

variable "etl_job_max_capacity" {
  description = "Maximum DPU capacity for the ETL job"
  type        = number
  default     = 10
  
  validation {
    condition     = var.etl_job_max_capacity >= 2 && var.etl_job_max_capacity <= 100
    error_message = "ETL job max capacity must be between 2 and 100 DPUs."
  }
}

variable "etl_job_timeout" {
  description = "Timeout for ETL job in minutes"
  type        = number
  default     = 60
  
  validation {
    condition     = var.etl_job_timeout >= 1 && var.etl_job_timeout <= 2880
    error_message = "ETL job timeout must be between 1 and 2880 minutes."
  }
}

variable "enable_workflow_scheduling" {
  description = "Enable automatic workflow scheduling"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_data_quality_rules" {
  description = "Enable AWS Glue Data Quality rules"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for pipeline notifications (leave empty to disable notifications)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "s3_storage_class" {
  description = "Default storage class for S3 objects"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING"], var.s3_storage_class)
    error_message = "Storage class must be one of: STANDARD, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}