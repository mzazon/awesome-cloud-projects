# Variables for Amazon Redshift Data Warehouse Infrastructure

# AWS Region Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner of the resources (for tagging purposes)"
  type        = string
  default     = "data-team"
}

# Redshift Serverless Configuration
variable "namespace_name" {
  description = "Name for the Redshift Serverless namespace"
  type        = string
  default     = ""
  
  validation {
    condition = var.namespace_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.namespace_name))
    error_message = "Namespace name must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "workgroup_name" {
  description = "Name for the Redshift Serverless workgroup"
  type        = string
  default     = ""
  
  validation {
    condition = var.workgroup_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workgroup_name))
    error_message = "Workgroup name must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_name" {
  description = "Name of the default database in the namespace"
  type        = string
  default     = "sampledb"

  validation {
    condition = can(regex("^[a-z][a-z0-9_]*$", var.database_name))
    error_message = "Database name must start with a lowercase letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "admin_username" {
  description = "Admin username for the Redshift database"
  type        = string
  default     = "awsuser"

  validation {
    condition = can(regex("^[a-z][a-z0-9_]*$", var.admin_username))
    error_message = "Admin username must start with a lowercase letter and contain only lowercase letters, numbers, and underscores."
  }
}

# Redshift Serverless Capacity Configuration
variable "base_capacity" {
  description = "Base capacity for the Redshift Serverless workgroup (measured in RPUs)"
  type        = number
  default     = 128

  validation {
    condition = var.base_capacity >= 32 && var.base_capacity <= 512 && var.base_capacity % 8 == 0
    error_message = "Base capacity must be between 32 and 512 RPUs and must be divisible by 8."
  }
}

variable "max_capacity" {
  description = "Maximum capacity for the Redshift Serverless workgroup (measured in RPUs)"
  type        = number
  default     = 512

  validation {
    condition = var.max_capacity >= 32 && var.max_capacity <= 512 && var.max_capacity % 8 == 0
    error_message = "Maximum capacity must be between 32 and 512 RPUs and must be divisible by 8."
  }
}

# Network Configuration
variable "publicly_accessible" {
  description = "Whether the Redshift workgroup should be publicly accessible"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Redshift workgroup (optional for private access)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for the Redshift workgroup (optional for private access)"
  type        = list(string)
  default     = []
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket to store sample data (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

# IAM Configuration
variable "iam_role_name" {
  description = "Name for the IAM role used by Redshift Serverless (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

# Monitoring and Logging
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for Redshift"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention values."
  }
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Whether to create and upload sample data files to S3"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for Redshift and S3 resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days after which the KMS key will be deleted (7-30 days)"
  type        = number
  default     = 7

  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Cost Management
variable "enable_usage_limits" {
  description = "Enable usage limits for cost control"
  type        = bool
  default     = true
}

variable "usage_limit_amount" {
  description = "Usage limit amount in Redshift Processing Units (RPU) hours per month"
  type        = number
  default     = 1000

  validation {
    condition = var.usage_limit_amount > 0
    error_message = "Usage limit amount must be greater than 0."
  }
}

variable "usage_limit_breach_action" {
  description = "Action to take when usage limit is breached (log, emit-metric, deactivate)"
  type        = string
  default     = "emit-metric"

  validation {
    condition = contains(["log", "emit-metric", "deactivate"], var.usage_limit_breach_action)
    error_message = "Usage limit breach action must be one of: log, emit-metric, deactivate."
  }
}