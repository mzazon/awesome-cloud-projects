variable "aws_region" {
  description = "AWS region where resources will be created"
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
  default     = "data-lake"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for S3 encryption (optional)"
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = "S3 lifecycle rules configuration"
  type = object({
    raw_zone_transitions = list(object({
      days          = number
      storage_class = string
    }))
    processed_zone_transitions = list(object({
      days          = number
      storage_class = string
    }))
  })
  default = {
    raw_zone_transitions = [
      {
        days          = 30
        storage_class = "STANDARD_IA"
      },
      {
        days          = 90
        storage_class = "GLACIER"
      },
      {
        days          = 365
        storage_class = "DEEP_ARCHIVE"
      }
    ]
    processed_zone_transitions = [
      {
        days          = 90
        storage_class = "STANDARD_IA"
      },
      {
        days          = 180
        storage_class = "GLACIER"
      }
    ]
  }
}

variable "glue_job_configuration" {
  description = "Configuration for Glue ETL jobs"
  type = object({
    max_capacity    = number
    timeout         = number
    python_version  = string
    enable_metrics  = bool
    enable_logs     = bool
  })
  default = {
    max_capacity    = 2
    timeout         = 60
    python_version  = "3"
    enable_metrics  = true
    enable_logs     = true
  }
}

variable "athena_workgroup_configuration" {
  description = "Configuration for Athena workgroup"
  type = object({
    enforce_workgroup_configuration = bool
    publish_cloudwatch_metrics     = bool
    bytes_scanned_cutoff_per_query = number
    result_configuration_encryption = bool
  })
  default = {
    enforce_workgroup_configuration = true
    publish_cloudwatch_metrics     = true
    bytes_scanned_cutoff_per_query = 104857600 # 100 MB
    result_configuration_encryption = true
  }
}

variable "crawler_schedule" {
  description = "Cron schedule for Glue crawlers (optional)"
  type        = string
  default     = null
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DataLake"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

variable "additional_s3_bucket_policies" {
  description = "Additional S3 bucket policies to apply"
  type        = list(string)
  default     = []
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for S3 buckets"
  type        = bool
  default     = false
}

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for resources"
  type        = bool
  default     = true
}