# Variables for Real-Time Data Processing with Kinesis Data Firehose

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "realtime-data-processing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# S3 Configuration
variable "s3_buffer_size" {
  description = "Buffer size in MB for S3 delivery stream"
  type        = number
  default     = 5
  
  validation {
    condition     = var.s3_buffer_size >= 1 && var.s3_buffer_size <= 128
    error_message = "S3 buffer size must be between 1 and 128 MB."
  }
}

variable "s3_buffer_interval" {
  description = "Buffer interval in seconds for S3 delivery stream"
  type        = number
  default     = 300
  
  validation {
    condition     = var.s3_buffer_interval >= 60 && var.s3_buffer_interval <= 900
    error_message = "S3 buffer interval must be between 60 and 900 seconds."
  }
}

variable "s3_compression_format" {
  description = "Compression format for S3 objects"
  type        = string
  default     = "GZIP"
  
  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.s3_compression_format)
    error_message = "Compression format must be one of: UNCOMPRESSED, GZIP, ZIP, Snappy, HADOOP_SNAPPY."
  }
}

# OpenSearch Configuration
variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch domain"
  type        = string
  default     = "t3.small.search"
  
  validation {
    condition     = can(regex("^(t3|t2|m5|m4|m3|r5|r4|r3|c5|c4|i3|i2)\\.(small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge)\\.search$", var.opensearch_instance_type))
    error_message = "OpenSearch instance type must be a valid search instance type."
  }
}

variable "opensearch_instance_count" {
  description = "Number of instances in OpenSearch domain"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "OpenSearch instance count must be between 1 and 20."
  }
}

variable "opensearch_volume_size" {
  description = "EBS volume size in GB for OpenSearch domain"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_volume_size >= 10 && var.opensearch_volume_size <= 1000
    error_message = "OpenSearch volume size must be between 10 and 1000 GB."
  }
}

variable "opensearch_buffer_size" {
  description = "Buffer size in MB for OpenSearch delivery stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_buffer_size >= 1 && var.opensearch_buffer_size <= 100
    error_message = "OpenSearch buffer size must be between 1 and 100 MB."
  }
}

variable "opensearch_buffer_interval" {
  description = "Buffer interval in seconds for OpenSearch delivery stream"
  type        = number
  default     = 60
  
  validation {
    condition     = var.opensearch_buffer_interval >= 60 && var.opensearch_buffer_interval <= 900
    error_message = "OpenSearch buffer interval must be between 60 and 900 seconds."
  }
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# Monitoring Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarms"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 3600, 21600, 86400], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

# Error Handling Configuration
variable "dlq_retention_seconds" {
  description = "Message retention in seconds for Dead Letter Queue"
  type        = number
  default     = 1209600  # 14 days
  
  validation {
    condition     = var.dlq_retention_seconds >= 60 && var.dlq_retention_seconds <= 1209600
    error_message = "DLQ retention must be between 60 seconds and 14 days."
  }
}

variable "dlq_visibility_timeout" {
  description = "Visibility timeout in seconds for Dead Letter Queue"
  type        = number
  default     = 300
  
  validation {
    condition     = var.dlq_visibility_timeout >= 0 && var.dlq_visibility_timeout <= 43200
    error_message = "DLQ visibility timeout must be between 0 and 43200 seconds."
  }
}

# Data Format Configuration
variable "enable_parquet_conversion" {
  description = "Enable Parquet format conversion for S3 storage"
  type        = bool
  default     = true
}

variable "enable_data_transformation" {
  description = "Enable Lambda data transformation"
  type        = bool
  default     = true
}

variable "enable_opensearch_backup" {
  description = "Enable S3 backup for OpenSearch delivery stream"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "enable_opensearch_encryption" {
  description = "Enable OpenSearch domain encryption"
  type        = bool
  default     = true
}

variable "opensearch_tls_policy" {
  description = "TLS security policy for OpenSearch domain"
  type        = string
  default     = "Policy-Min-TLS-1-2-2019-07"
  
  validation {
    condition     = contains(["Policy-Min-TLS-1-0-2019-07", "Policy-Min-TLS-1-2-2019-07"], var.opensearch_tls_policy)
    error_message = "TLS policy must be either Policy-Min-TLS-1-0-2019-07 or Policy-Min-TLS-1-2-2019-07."
  }
}

# Cost Optimization Configuration
variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning S3 objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 1 && var.s3_lifecycle_transition_days <= 365
    error_message = "S3 lifecycle transition days must be between 1 and 365."
  }
}

variable "s3_lifecycle_glacier_days" {
  description = "Number of days before transitioning S3 objects to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_glacier_days >= 1 && var.s3_lifecycle_glacier_days <= 365
    error_message = "S3 lifecycle Glacier transition days must be between 1 and 365."
  }
}

variable "s3_lifecycle_deep_archive_days" {
  description = "Number of days before transitioning S3 objects to Deep Archive"
  type        = number
  default     = 365
  
  validation {
    condition     = var.s3_lifecycle_deep_archive_days >= 1 && var.s3_lifecycle_deep_archive_days <= 3650
    error_message = "S3 lifecycle Deep Archive transition days must be between 1 and 3650."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring S3 objects"
  type        = number
  default     = 2555  # 7 years
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 1 && var.s3_lifecycle_expiration_days <= 3650
    error_message = "S3 lifecycle expiration days must be between 1 and 3650."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform = "true"
    Recipe    = "real-time-data-processing-kinesis-data-firehose"
  }
}

# Advanced Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for all resources"
  type        = bool
  default     = true
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for S3 bucket"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "AWS region for backup resources (if cross-region replication is enabled)"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.backup_region))
    error_message = "Backup region must be a valid AWS region identifier."
  }
}

# Custom processor configuration
variable "custom_processors" {
  description = "Custom processors for data transformation"
  type = list(object({
    type       = string
    parameters = map(string)
  }))
  default = []
}

# Index configuration for OpenSearch
variable "opensearch_index_rotation" {
  description = "Index rotation period for OpenSearch"
  type        = string
  default     = "OneDay"
  
  validation {
    condition     = contains(["NoRotation", "OneHour", "OneDay", "OneWeek", "OneMonth"], var.opensearch_index_rotation)
    error_message = "OpenSearch index rotation must be one of: NoRotation, OneHour, OneDay, OneWeek, OneMonth."
  }
}