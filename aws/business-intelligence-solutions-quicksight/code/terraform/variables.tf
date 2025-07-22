# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^(us|eu|ap|sa|ca|me|af|il)-(north|south|east|west|central|northeast|northwest|southeast|southwest)-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "quicksight-bi"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket storing sample data (will be made unique with random suffix)"
  type        = string
  default     = "quicksight-bi-data"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.s3_bucket_name))
    error_message = "S3 bucket name must be 3-40 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management for cost optimization"
  type        = bool
  default     = true
}

# RDS Configuration
variable "create_rds_instance" {
  description = "Whether to create an RDS instance for additional data source"
  type        = bool
  default     = false
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.(t3|t4g|m5|m6i|r5|r6i)\\.(micro|small|medium|large|xlarge|2xlarge)$", var.rds_instance_class))
    error_message = "RDS instance class must be a valid instance type."
  }
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.rds_allocated_storage >= 20 && var.rds_allocated_storage <= 1000
    error_message = "RDS allocated storage must be between 20 and 1000 GB."
  }
}

variable "rds_engine" {
  description = "RDS database engine"
  type        = string
  default     = "mysql"

  validation {
    condition     = contains(["mysql", "postgres", "mariadb"], var.rds_engine)
    error_message = "RDS engine must be one of: mysql, postgres, mariadb."
  }
}

variable "rds_engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "8.0"
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.rds_backup_retention_period >= 0 && var.rds_backup_retention_period <= 35
    error_message = "RDS backup retention period must be between 0 and 35 days."
  }
}

# QuickSight Configuration
variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.quicksight_edition)
    error_message = "QuickSight edition must be either STANDARD or ENTERPRISE."
  }
}

variable "quicksight_authentication_method" {
  description = "QuickSight authentication method"
  type        = string
  default     = "IAM_AND_QUICKSIGHT"

  validation {
    condition     = contains(["IAM_AND_QUICKSIGHT", "IAM_ONLY"], var.quicksight_authentication_method)
    error_message = "QuickSight authentication method must be either IAM_AND_QUICKSIGHT or IAM_ONLY."
  }
}

variable "enable_quicksight_spice" {
  description = "Enable SPICE for improved query performance"
  type        = bool
  default     = true
}

variable "quicksight_session_timeout" {
  description = "QuickSight session timeout in minutes for embedded analytics"
  type        = number
  default     = 60

  validation {
    condition     = var.quicksight_session_timeout >= 15 && var.quicksight_session_timeout <= 600
    error_message = "QuickSight session timeout must be between 15 and 600 minutes."
  }
}

# Data refresh configuration
variable "enable_scheduled_refresh" {
  description = "Enable scheduled data refresh for QuickSight datasets"
  type        = bool
  default     = true
}

variable "refresh_schedule_frequency" {
  description = "Data refresh frequency (DAILY, WEEKLY, MONTHLY)"
  type        = string
  default     = "DAILY"

  validation {
    condition     = contains(["DAILY", "WEEKLY", "MONTHLY"], var.refresh_schedule_frequency)
    error_message = "Refresh schedule frequency must be one of: DAILY, WEEKLY, MONTHLY."
  }
}

variable "refresh_time_of_day" {
  description = "Time of day for scheduled refresh (24-hour format, e.g., 06:00)"
  type        = string
  default     = "06:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.refresh_time_of_day))
    error_message = "Refresh time must be in HH:MM format (24-hour)."
  }
}

# Security and access configuration
variable "enable_dashboard_sharing" {
  description = "Enable dashboard sharing capabilities"
  type        = bool
  default     = true
}

variable "enable_embedded_analytics" {
  description = "Enable embedded analytics functionality"
  type        = bool
  default     = true
}

variable "allowed_embed_domains" {
  description = "List of domains allowed for embedded analytics"
  type        = list(string)
  default     = ["*"]
}

variable "enable_row_level_security" {
  description = "Enable row-level security for datasets"
  type        = bool
  default     = false
}

# Monitoring and alerting
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring for infrastructure components"
  type        = bool
  default     = true
}

variable "enable_cost_monitoring" {
  description = "Enable cost monitoring and alerts"
  type        = bool
  default     = true
}

variable "cost_alert_threshold" {
  description = "Monthly cost alert threshold in USD"
  type        = number
  default     = 100

  validation {
    condition     = var.cost_alert_threshold > 0
    error_message = "Cost alert threshold must be greater than 0."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for notifications and alerts"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}