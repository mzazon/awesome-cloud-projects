# Variables for DynamoDB Global Tables Infrastructure
# This file defines all configurable parameters for the global NoSQL database architecture

# -----------------------------------------------------------------------------
# General Configuration Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "global-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# -----------------------------------------------------------------------------
# Regional Configuration Variables
# -----------------------------------------------------------------------------

variable "primary_region" {
  description = "Primary AWS region for the Global Table"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for the Global Table"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for the Global Table"
  type        = string
  default     = "ap-southeast-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region format."
  }
}

# -----------------------------------------------------------------------------
# DynamoDB Configuration Variables
# -----------------------------------------------------------------------------

variable "table_name" {
  description = "Name of the DynamoDB table (will be made unique with random suffix)"
  type        = string
  default     = "global-app-data"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.table_name))
    error_message = "Table name must contain only alphanumeric characters, hyphens, periods, and underscores."
  }
}

variable "read_capacity" {
  description = "Read capacity units for the DynamoDB table"
  type        = number
  default     = 10
  
  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 40000
    error_message = "Read capacity must be between 1 and 40,000."
  }
}

variable "write_capacity" {
  description = "Write capacity units for the DynamoDB table"
  type        = number
  default     = 10
  
  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 40000
    error_message = "Write capacity must be between 1 and 40,000."
  }
}

variable "gsi_read_capacity" {
  description = "Read capacity units for Global Secondary Index"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_read_capacity >= 1 && var.gsi_read_capacity <= 40000
    error_message = "GSI read capacity must be between 1 and 40,000."
  }
}

variable "gsi_write_capacity" {
  description = "Write capacity units for Global Secondary Index"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_write_capacity >= 1 && var.gsi_write_capacity <= 40000
    error_message = "GSI write capacity must be between 1 and 40,000."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for DynamoDB table"
  type        = bool
  default     = true
}

variable "stream_view_type" {
  description = "Stream view type for DynamoDB streams"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
  
  validation {
    condition = contains([
      "KEYS_ONLY",
      "NEW_IMAGE",
      "OLD_IMAGE",
      "NEW_AND_OLD_IMAGES"
    ], var.stream_view_type)
    error_message = "Stream view type must be one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

# -----------------------------------------------------------------------------
# Monitoring Configuration Variables
# -----------------------------------------------------------------------------

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "read_throttle_threshold" {
  description = "Threshold for read throttling alarms"
  type        = number
  default     = 5
}

variable "write_throttle_threshold" {
  description = "Threshold for write throttling alarms"
  type        = number
  default     = 5
}

variable "replication_delay_threshold" {
  description = "Threshold for replication delay alarms (in milliseconds)"
  type        = number
  default     = 1000
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for alarms"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period for alarm evaluation (in seconds)"
  type        = number
  default     = 300
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Backup Configuration Variables
# -----------------------------------------------------------------------------

variable "enable_backup" {
  description = "Enable AWS Backup for DynamoDB table"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "cron(0 2 ? * * *)"
}

variable "backup_start_window" {
  description = "Backup start window in minutes"
  type        = number
  default     = 60
}

variable "backup_completion_window" {
  description = "Backup completion window in minutes"
  type        = number
  default     = 120
}

# -----------------------------------------------------------------------------
# Lambda Configuration Variables
# -----------------------------------------------------------------------------

variable "enable_lambda_demo" {
  description = "Enable Lambda function for demonstrating Global Tables"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function (in seconds)"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function (in MB)"
  type        = number
  default     = 128
}

# -----------------------------------------------------------------------------
# Security Configuration Variables
# -----------------------------------------------------------------------------

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for DynamoDB (requires VPC configuration)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Tagging Configuration Variables
# -----------------------------------------------------------------------------

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DynamoDB Global Tables"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Recipe      = "nosql-database-architectures-dynamodb-global-tables"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Cost Optimization Variables
# -----------------------------------------------------------------------------

variable "enable_auto_scaling" {
  description = "Enable auto scaling for DynamoDB table"
  type        = bool
  default     = false
}

variable "auto_scaling_min_capacity" {
  description = "Minimum capacity for auto scaling"
  type        = number
  default     = 1
}

variable "auto_scaling_max_capacity" {
  description = "Maximum capacity for auto scaling"
  type        = number
  default     = 100
}

variable "auto_scaling_target_utilization" {
  description = "Target utilization percentage for auto scaling"
  type        = number
  default     = 70
}