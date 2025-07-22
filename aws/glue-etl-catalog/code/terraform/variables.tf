# Variables for AWS Glue ETL Pipeline Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "etl-pipeline"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "glue_database_name" {
  description = "Name for the Glue database"
  type        = string
  default     = null
}

variable "enable_data_quality" {
  description = "Enable Glue Data Quality features"
  type        = bool
  default     = true
}

variable "crawler_schedule" {
  description = "Schedule for running crawlers (cron expression)"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
  
  validation {
    condition = can(regex("^cron\\(", var.crawler_schedule))
    error_message = "Crawler schedule must be a valid cron expression starting with 'cron('."
  }
}

variable "etl_job_timeout" {
  description = "Timeout for ETL job in minutes"
  type        = number
  default     = 60
  
  validation {
    condition = var.etl_job_timeout >= 1 && var.etl_job_timeout <= 2880
    error_message = "ETL job timeout must be between 1 and 2880 minutes."
  }
}

variable "etl_job_max_retries" {
  description = "Maximum number of retries for ETL job"
  type        = number
  default     = 1
  
  validation {
    condition = var.etl_job_max_retries >= 0 && var.etl_job_max_retries <= 10
    error_message = "ETL job max retries must be between 0 and 10."
  }
}

variable "glue_version" {
  description = "AWS Glue version to use"
  type        = string
  default     = "4.0"
  
  validation {
    condition = contains(["2.0", "3.0", "4.0"], var.glue_version)
    error_message = "Glue version must be one of: 2.0, 3.0, 4.0."
  }
}

variable "worker_type" {
  description = "Type of predefined worker for Glue job"
  type        = string
  default     = "G.1X"
  
  validation {
    condition = contains(["Standard", "G.1X", "G.2X", "G.025X"], var.worker_type)
    error_message = "Worker type must be one of: Standard, G.1X, G.2X, G.025X."
  }
}

variable "number_of_workers" {
  description = "Number of workers for Glue job"
  type        = number
  default     = 2
  
  validation {
    condition = var.number_of_workers >= 2 && var.number_of_workers <= 299
    error_message = "Number of workers must be between 2 and 299."
  }
}

variable "s3_force_destroy" {
  description = "Force destroy S3 buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management on S3 buckets"
  type        = bool
  default     = true
}

variable "raw_data_transition_days" {
  description = "Number of days before transitioning raw data to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.raw_data_transition_days >= 1
    error_message = "Raw data transition days must be at least 1."
  }
}

variable "processed_data_transition_days" {
  description = "Number of days before transitioning processed data to IA storage"
  type        = number
  default     = 90
  
  validation {
    condition = var.processed_data_transition_days >= 1
    error_message = "Processed data transition days must be at least 1."
  }
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for Glue jobs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}