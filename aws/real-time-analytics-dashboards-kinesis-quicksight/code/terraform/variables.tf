# Variable definitions for real-time analytics dashboards infrastructure
# These variables allow customization of the streaming analytics solution

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z][a-z]-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "analytics-dashboard"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis Data Stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Kinesis shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Retention period must be between 24 and 8760 hours."
  }
}

variable "flink_parallelism" {
  description = "Parallelism setting for Flink application"
  type        = number
  default     = 1
  
  validation {
    condition     = var.flink_parallelism >= 1 && var.flink_parallelism <= 64
    error_message = "Flink parallelism must be between 1 and 64."
  }
}

variable "flink_parallelism_per_kpu" {
  description = "Parallelism per KPU for Flink application"
  type        = number
  default     = 1
  
  validation {
    condition     = var.flink_parallelism_per_kpu >= 1 && var.flink_parallelism_per_kpu <= 8
    error_message = "Parallelism per KPU must be between 1 and 8."
  }
}

variable "flink_auto_scaling_enabled" {
  description = "Enable auto-scaling for Flink application"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management for analytics data"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Days before transitioning objects to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Days before transitioning objects to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "s3_expiration_days" {
  description = "Days before expiring objects (0 = no expiration)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.s3_expiration_days == 0 || var.s3_expiration_days >= 90
    error_message = "Expiration must be 0 (disabled) or at least 90 days."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Kinesis and Flink"
  type        = bool
  default     = false
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for S3 and Kinesis"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "flink_jar_key" {
  description = "S3 key for the Flink application JAR file"
  type        = string
  default     = "flink-analytics-app-1.0.jar"
}

variable "flink_log_level" {
  description = "Log level for Flink application (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.flink_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "flink_metrics_level" {
  description = "Metrics level for Flink application (APPLICATION, TASK, OPERATOR, PARALLELISM)"
  type        = string
  default     = "APPLICATION"
  
  validation {
    condition     = contains(["APPLICATION", "TASK", "OPERATOR", "PARALLELISM"], var.flink_metrics_level)
    error_message = "Metrics level must be one of: APPLICATION, TASK, OPERATOR, PARALLELISM."
  }
}