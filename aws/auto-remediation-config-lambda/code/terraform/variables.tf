# Variables for AWS Config Auto-Remediation Infrastructure
# This file defines all customizable parameters for the deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "config-auto-remediation"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_config_global_recording" {
  description = "Whether to enable global resource recording in Config"
  type        = bool
  default     = true
}

variable "config_delivery_frequency" {
  description = "Frequency for Config to deliver configuration snapshots"
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours",
      "Twelve_Hours", "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Delivery frequency must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}

variable "auto_remediation_enabled" {
  description = "Enable automatic remediation for Config rules"
  type        = bool
  default     = true
}

variable "max_remediation_attempts" {
  description = "Maximum number of automatic remediation attempts"
  type        = number
  default     = 3

  validation {
    condition     = var.max_remediation_attempts >= 1 && var.max_remediation_attempts <= 10
    error_message = "Maximum remediation attempts must be between 1 and 10."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda remediation functions in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "sns_email_notifications" {
  description = "List of email addresses to receive compliance notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.sns_email_notifications : can(regex("^[^@]+@[^@]+\\.[^@]+$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "config_rules_enabled" {
  description = "Map of Config rules to enable"
  type = object({
    security_group_ssh_restricted      = bool
    s3_bucket_public_access_prohibited = bool
    root_access_key_check              = bool
    iam_password_policy                = bool
  })
  default = {
    security_group_ssh_restricted      = true
    s3_bucket_public_access_prohibited = true
    root_access_key_check              = true
    iam_password_policy                = true
  }
}

variable "resource_types_to_record" {
  description = "List of AWS resource types to record in Config"
  type        = list(string)
  default = [
    "AWS::EC2::SecurityGroup",
    "AWS::S3::Bucket",
    "AWS::IAM::Role",
    "AWS::IAM::Policy",
    "AWS::IAM::User",
    "AWS::RDS::DBInstance",
    "AWS::Lambda::Function"
  ]
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "aws-config"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_server_side_encryption" {
  description = "Enable server-side encryption for Config S3 bucket"
  type        = bool
  default     = true
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}