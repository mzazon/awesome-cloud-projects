# General Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "created_by" {
  description = "IAM user or role creating this infrastructure"
  type        = string
  default     = "terraform"
}

variable "project_name" {
  description = "Name of the business continuity testing project"
  type        = string
  default     = "bc-testing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Testing Configuration
variable "notification_email" {
  description = "Email address for BC testing notifications"
  type        = string

  validation {
    condition     = can(regex("^[\\w\\.-]+@[a-zA-Z\\d\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "test_schedules" {
  description = "Cron expressions for different types of BC tests"
  type = object({
    daily_tests       = string
    weekly_tests      = string
    monthly_tests     = string
    compliance_report = string
  })
  default = {
    daily_tests       = "rate(1 day)"
    weekly_tests      = "cron(0 2 ? * SUN *)"
    monthly_tests     = "cron(0 1 1 * ? *)"
    compliance_report = "cron(0 8 1 * ? *)"
  }
}

# Resource Configuration
variable "test_instance_id" {
  description = "EC2 instance ID for backup validation testing (optional)"
  type        = string
  default     = ""
}

variable "backup_vault_name" {
  description = "AWS Backup vault name for testing (optional)"
  type        = string
  default     = "default"
}

variable "db_instance_identifier" {
  description = "RDS instance identifier for database recovery testing (optional)"
  type        = string
  default     = ""
}

variable "primary_alb_arn" {
  description = "Primary Application Load Balancer ARN for failover testing (optional)"
  type        = string
  default     = ""
}

variable "secondary_alb_arn" {
  description = "Secondary Application Load Balancer ARN for failover testing (optional)"
  type        = string
  default     = ""
}

variable "route53_hosted_zone_id" {
  description = "Route 53 hosted zone ID for DNS failover testing (optional)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for application failover testing (optional)"
  type        = string
  default     = ""
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for test results"
  type        = bool
  default     = true
}

variable "s3_lifecycle_rules" {
  description = "S3 lifecycle configuration for test results"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
    expiration_days           = number
  })
  default = {
    transition_to_ia_days      = 30
    transition_to_glacier_days = 90
    expiration_days           = 2555  # ~7 years
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 900

  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and other resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}