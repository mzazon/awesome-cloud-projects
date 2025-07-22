# Variables for AWS Secrets Manager Infrastructure
# This file defines all input variables for the Terraform configuration

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "secrets-manager-demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "secret_name" {
  description = "Name of the secret to create"
  type        = string
  default     = ""
  
  validation {
    condition = var.secret_name == "" || can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.secret_name))
    error_message = "Secret name must contain only letters, numbers, and the following characters: /_+=.@-"
  }
}

variable "database_config" {
  description = "Database configuration for the secret"
  type = object({
    engine   = string
    host     = string
    username = string
    dbname   = string
    port     = number
  })
  default = {
    engine   = "mysql"
    host     = "demo-database.cluster-abc123.us-east-1.rds.amazonaws.com"
    username = "admin"
    dbname   = "myapp"
    port     = 3306
  }
}

variable "password_length" {
  description = "Length of the generated password"
  type        = number
  default     = 20
  
  validation {
    condition = var.password_length >= 8 && var.password_length <= 128
    error_message = "Password length must be between 8 and 128 characters."
  }
}

variable "rotation_schedule" {
  description = "CloudWatch schedule expression for automatic rotation"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition = can(regex("^(rate|cron)\\(.*\\)$", var.rotation_schedule))
    error_message = "Rotation schedule must be a valid CloudWatch schedule expression."
  }
}

variable "enable_rotation" {
  description = "Whether to enable automatic rotation"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "cross_account_principals" {
  description = "List of AWS account IDs or ARNs to grant cross-account access"
  type        = list(string)
  default     = []
}

variable "enable_monitoring" {
  description = "Whether to create CloudWatch dashboard and alarms"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}