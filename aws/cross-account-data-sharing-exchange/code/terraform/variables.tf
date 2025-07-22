# Variables for AWS Data Exchange cross-account data sharing infrastructure

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "subscriber_account_id" {
  description = "AWS account ID of the data subscriber (12-digit account ID)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.subscriber_account_id))
    error_message = "Subscriber account ID must be a 12-digit AWS account ID."
  }
}

variable "dataset_name" {
  description = "Name for the AWS Data Exchange dataset"
  type        = string
  default     = ""

  validation {
    condition     = var.dataset_name == "" || can(regex("^[a-zA-Z0-9_-]{1,255}$", var.dataset_name))
    error_message = "Dataset name must be 1-255 characters and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "provider_bucket_name" {
  description = "Name for the S3 bucket used by the data provider (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "subscriber_bucket_name" {
  description = "Name for the S3 bucket used by the data subscriber (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "data_grant_expires_at" {
  description = "Expiration date and time for the data grant (ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ)"
  type        = string
  default     = "2024-12-31T23:59:59Z"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.data_grant_expires_at))
    error_message = "Data grant expiration must be in ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation in MB for Lambda functions"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for automated data updates"
  type        = string
  default     = "rate(24 hours)"

  validation {
    condition     = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.schedule_expression))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

variable "sample_data_enabled" {
  description = "Whether to create and upload sample data files to S3"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "data-exchange-cross-account-sharing"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to specific resources"
  type        = map(string)
  default     = {}
}

# Local values for computed configurations
locals {
  # Generate random suffix for unique resource naming
  random_suffix = random_string.suffix.result

  # Compute resource names with random suffix if not provided
  dataset_name           = var.dataset_name != "" ? var.dataset_name : "enterprise-analytics-data-${local.random_suffix}"
  provider_bucket_name   = var.provider_bucket_name != "" ? var.provider_bucket_name : "data-exchange-provider-${local.random_suffix}"
  subscriber_bucket_name = var.subscriber_bucket_name != "" ? var.subscriber_bucket_name : "data-exchange-subscriber-${local.random_suffix}"

  # Common tags for all resources
  common_tags = merge(
    var.default_tags,
    var.additional_tags,
    {
      Recipe = "cross-account-data-sharing-aws-data-exchange"
    }
  )

  # Sample data configuration
  sample_data = {
    "analytics-data/customer-analytics.csv" = "customer_id,purchase_date,amount,category,region\nC001,2024-01-15,150.50,electronics,us-east\nC002,2024-01-16,89.99,books,us-west\nC003,2024-01-17,299.99,clothing,eu-central\nC004,2024-01-18,45.75,home,us-east\nC005,2024-01-19,199.99,electronics,asia-pacific"
    "analytics-data/sales-summary.json"    = jsonencode({
      report_date          = "2024-01-31"
      total_sales          = 785.72
      transaction_count    = 5
      top_category         = "electronics"
      average_order_value  = 157.14
    })
  }
}