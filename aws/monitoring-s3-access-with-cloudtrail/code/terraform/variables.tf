# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 Configuration
variable "source_bucket_name" {
  description = "Name of the source S3 bucket to monitor (optional - will generate unique name if not provided)"
  type        = string
  default     = ""
}

variable "logs_bucket_name" {
  description = "Name of the S3 bucket for access logs (optional - will generate unique name if not provided)"
  type        = string
  default     = ""
}

variable "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs (optional - will generate unique name if not provided)"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

# CloudTrail Configuration
variable "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  type        = string
  default     = "s3-security-monitoring-trail"
}

variable "include_global_service_events" {
  description = "Include global service events in CloudTrail"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Make CloudTrail a multi-region trail"
  type        = bool
  default     = true
}

variable "enable_log_file_validation" {
  description = "Enable CloudTrail log file validation"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs integration for CloudTrail"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch logs retention days must be a valid value."
  }
}

# EventBridge Configuration
variable "enable_security_monitoring" {
  description = "Enable EventBridge rules for security monitoring"
  type        = bool
  default     = true
}

variable "security_alert_email" {
  description = "Email address for security alerts (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.security_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "Security alert email must be a valid email address or empty."
  }
}

# Lambda Configuration
variable "enable_lambda_monitoring" {
  description = "Enable Lambda function for advanced security monitoring"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

# CloudWatch Dashboard Configuration
variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
  default     = "S3SecurityMonitoring"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}