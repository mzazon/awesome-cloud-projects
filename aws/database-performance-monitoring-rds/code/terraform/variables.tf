# General Configuration
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "rds-performance-insights"
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
  validation {
    condition     = can(regex("^db\\.(t3|t4g|m5|m6i|r5|r6i)\\.(nano|micro|small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge)$", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_engine" {
  description = "Database engine"
  type        = string
  default     = "mysql"
  validation {
    condition     = contains(["mysql", "postgres", "oracle-ee", "oracle-se2", "oracle-se1", "oracle-se", "sqlserver-ee", "sqlserver-se", "sqlserver-ex", "sqlserver-web"], var.db_engine)
    error_message = "Database engine must be a supported RDS engine type."
  }
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0.35"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  default     = "SecurePassword123!"
  sensitive   = true
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "db_publicly_accessible" {
  description = "Whether the database should be publicly accessible"
  type        = bool
  default     = false
}

# Performance Insights Configuration
variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data"
  type        = number
  default     = 7
  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 (free tier) or a valid paid tier value."
  }
}

# Enhanced Monitoring Configuration
variable "monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected"
  type        = number
  default     = 60
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# EventBridge Configuration
variable "analysis_schedule" {
  description = "EventBridge schedule expression for performance analysis"
  type        = string
  default     = "rate(15 minutes)"
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.analysis_schedule))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for performance alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Email address must be valid or empty."
  }
}

# CloudWatch Alarms Configuration
variable "cpu_threshold" {
  description = "CPU utilization threshold for alarms"
  type        = number
  default     = 75.0
  validation {
    condition     = var.cpu_threshold >= 0 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "connection_threshold" {
  description = "Database connection threshold for alarms"
  type        = number
  default     = 80
  validation {
    condition     = var.connection_threshold >= 1 && var.connection_threshold <= 1000
    error_message = "Connection threshold must be between 1 and 1000."
  }
}

variable "high_load_events_threshold" {
  description = "Threshold for high load events custom metric"
  type        = number
  default     = 5
  validation {
    condition     = var.high_load_events_threshold >= 1 && var.high_load_events_threshold <= 100
    error_message = "High load events threshold must be between 1 and 100."
  }
}

variable "problematic_queries_threshold" {
  description = "Threshold for problematic queries custom metric"
  type        = number
  default     = 3
  validation {
    condition     = var.problematic_queries_threshold >= 1 && var.problematic_queries_threshold <= 50
    error_message = "Problematic queries threshold must be between 1 and 50."
  }
}

# S3 Configuration
variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID for database deployment (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for database deployment (leave empty to use default subnets)"
  type        = list(string)
  default     = []
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}