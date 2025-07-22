#===============================================================================
# CORE VARIABLES
#===============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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
  default     = "financial-analytics"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

#===============================================================================
# S3 CONFIGURATION
#===============================================================================

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets for data integrity"
  type        = bool
  default     = true
}

variable "enable_s3_lifecycle" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_ia_days" {
  description = "Number of days before transitioning objects to Infrequent Access storage class"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_transition_ia_days >= 30
    error_message = "S3 IA transition must be at least 30 days."
  }
}

variable "s3_transition_glacier_days" {
  description = "Number of days before transitioning objects to Glacier storage class"
  type        = number
  default     = 90

  validation {
    condition     = var.s3_transition_glacier_days >= 90
    error_message = "S3 Glacier transition must be at least 90 days."
  }
}

#===============================================================================
# LAMBDA CONFIGURATION
#===============================================================================

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"

  validation {
    condition     = can(regex("^python3\\.(8|9|10|11)$", var.lambda_runtime))
    error_message = "Lambda runtime must be a supported Python version (3.8, 3.9, 3.10, or 3.11)."
  }
}

variable "cost_collector_timeout" {
  description = "Timeout for cost data collector Lambda function (seconds)"
  type        = number
  default     = 900

  validation {
    condition     = var.cost_collector_timeout >= 60 && var.cost_collector_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "cost_collector_memory" {
  description = "Memory allocation for cost data collector Lambda function (MB)"
  type        = number
  default     = 1024

  validation {
    condition     = var.cost_collector_memory >= 128 && var.cost_collector_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "data_transformer_timeout" {
  description = "Timeout for data transformer Lambda function (seconds)"
  type        = number
  default     = 900

  validation {
    condition     = var.data_transformer_timeout >= 60 && var.data_transformer_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "data_transformer_memory" {
  description = "Memory allocation for data transformer Lambda function (MB)"
  type        = number
  default     = 2048

  validation {
    condition     = var.data_transformer_memory >= 128 && var.data_transformer_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

#===============================================================================
# EVENTBRIDGE SCHEDULING CONFIGURATION
#===============================================================================

variable "cost_collection_schedule" {
  description = "EventBridge schedule expression for daily cost data collection"
  type        = string
  default     = "cron(0 6 * * ? *)" # Daily at 6 AM UTC

  validation {
    condition     = can(regex("^(cron|rate)\\(.+\\)$", var.cost_collection_schedule))
    error_message = "Schedule expression must be a valid EventBridge cron or rate expression."
  }
}

variable "data_transformation_schedule" {
  description = "EventBridge schedule expression for weekly data transformation"
  type        = string
  default     = "cron(0 7 ? * SUN *)" # Weekly on Sunday at 7 AM UTC

  validation {
    condition     = can(regex("^(cron|rate)\\(.+\\)$", var.data_transformation_schedule))
    error_message = "Schedule expression must be a valid EventBridge cron or rate expression."
  }
}

variable "enable_automated_scheduling" {
  description = "Enable automated EventBridge scheduling for data collection and transformation"
  type        = bool
  default     = true
}

#===============================================================================
# ATHENA CONFIGURATION
#===============================================================================

variable "athena_workgroup_name" {
  description = "Name for the Athena workgroup for financial analytics"
  type        = string
  default     = "FinancialAnalytics"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.athena_workgroup_name))
    error_message = "Athena workgroup name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "enable_athena_cloudwatch_metrics" {
  description = "Enable CloudWatch metrics publishing for Athena workgroup"
  type        = bool
  default     = true
}

#===============================================================================
# GLUE DATA CATALOG CONFIGURATION
#===============================================================================

variable "glue_database_name" {
  description = "Name for the Glue database for financial analytics"
  type        = string
  default     = "financial_analytics"

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.glue_database_name))
    error_message = "Glue database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_database_description" {
  description = "Description for the Glue database"
  type        = string
  default     = "Financial analytics database for AWS cost data processing and analysis"
}

#===============================================================================
# QUICKSIGHT CONFIGURATION
#===============================================================================

variable "quicksight_namespace" {
  description = "QuickSight namespace for resource organization"
  type        = string
  default     = "default"
}

variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = can(regex("^(STANDARD|ENTERPRISE)$", var.quicksight_edition))
    error_message = "QuickSight edition must be either STANDARD or ENTERPRISE."
  }
}

variable "enable_quicksight_resources" {
  description = "Enable creation of QuickSight data sources and datasets"
  type        = bool
  default     = true
}

#===============================================================================
# COST EXPLORER CONFIGURATION
#===============================================================================

variable "cost_data_lookback_days" {
  description = "Number of days to look back for cost data collection"
  type        = number
  default     = 90

  validation {
    condition     = var.cost_data_lookback_days >= 1 && var.cost_data_lookback_days <= 365
    error_message = "Cost data lookback days must be between 1 and 365."
  }
}

variable "cost_granularity" {
  description = "Granularity for cost data collection (DAILY, MONTHLY)"
  type        = string
  default     = "DAILY"

  validation {
    condition     = can(regex("^(DAILY|MONTHLY)$", var.cost_granularity))
    error_message = "Cost granularity must be either DAILY or MONTHLY."
  }
}

#===============================================================================
# SECURITY AND COMPLIANCE
#===============================================================================

variable "enable_bucket_encryption" {
  description = "Enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for audit purposes"
  type        = bool
  default     = false
}

#===============================================================================
# NOTIFICATION CONFIGURATION
#===============================================================================

variable "notification_email" {
  description = "Email address for cost alerts and notifications"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification email must be a valid email address."
  }
}

variable "enable_cost_alerts" {
  description = "Enable cost alert notifications via SNS"
  type        = bool
  default     = false
}

#===============================================================================
# TAGGING
#===============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_allocation_tags" {
  description = "Tags used for cost allocation and departmental reporting"
  type = object({
    department  = string
    project     = string
    environment = string
  })
  default = {
    department  = "Finance"
    project     = "CostAnalytics"
    environment = "Production"
  }
}

#===============================================================================
# PERFORMANCE TUNING
#===============================================================================

variable "enable_reserved_capacity" {
  description = "Enable reserved capacity for predictable workloads"
  type        = bool
  default     = false
}

variable "athena_bytes_scanned_cutoff" {
  description = "Data scanned cutoff for Athena queries (bytes)"
  type        = number
  default     = 10737418240 # 10 GB

  validation {
    condition     = var.athena_bytes_scanned_cutoff > 0
    error_message = "Athena bytes scanned cutoff must be greater than 0."
  }
}

#===============================================================================
# MONITORING AND LOGGING
#===============================================================================

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring and logging for all components"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}