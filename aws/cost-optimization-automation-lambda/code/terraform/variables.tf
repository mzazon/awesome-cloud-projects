# Core configuration variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "cost-optimization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

# Lambda function configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# DynamoDB configuration
variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 5
}

# EventBridge scheduler configuration
variable "analysis_schedule_expression" {
  description = "Schedule expression for cost analysis (EventBridge format)"
  type        = string
  default     = "rate(1 day)"
}

variable "comprehensive_analysis_schedule_expression" {
  description = "Schedule expression for comprehensive analysis (EventBridge format)"
  type        = string
  default     = "rate(7 days)"
}

# Notification configuration
variable "notification_email" {
  description = "Email address for cost optimization notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# Auto-remediation configuration
variable "enable_auto_remediation" {
  description = "Enable automatic remediation for approved actions"
  type        = bool
  default     = false
}

variable "auto_remediation_checks" {
  description = "List of Trusted Advisor checks that can be auto-remediated"
  type        = list(string)
  default = [
    "EC2 instances stopped",
    "EBS volumes unattached",
    "RDS idle DB instances"
  ]
}

# S3 configuration
variable "s3_bucket_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "s3_bucket_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

# CloudWatch configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Cost thresholds
variable "cost_alert_threshold" {
  description = "Cost threshold in USD for alerts"
  type        = number
  default     = 100.0
}

variable "high_savings_threshold" {
  description = "Savings threshold in USD for high-priority alerts"
  type        = number
  default     = 50.0
}

# Tagging
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "cost-optimization-automation"
    ManagedBy   = "terraform"
    Component   = "cost-optimization"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}