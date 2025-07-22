# Variables for QuickSight Business Intelligence Dashboard Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "quicksight-bi-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "quicksight_account_edition" {
  description = "QuickSight account edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.quicksight_account_edition)
    error_message = "QuickSight edition must be STANDARD or ENTERPRISE."
  }
}

variable "quicksight_account_name" {
  description = "Display name for the QuickSight account"
  type        = string
  default     = "QuickSight Demo Account"
}

variable "quicksight_notification_email" {
  description = "Email address for QuickSight notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.quicksight_notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket and all objects (use with caution)"
  type        = bool
  default     = false
}

variable "create_sample_data" {
  description = "Create sample sales data in S3 bucket"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS instance class for the PostgreSQL database"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.rds_instance_class))
    error_message = "RDS instance class must be in the format db.instance_family.size."
  }
}

variable "rds_allocated_storage" {
  description = "Allocated storage in GB for RDS instance"
  type        = number
  default     = 20
  
  validation {
    condition     = var.rds_allocated_storage >= 20 && var.rds_allocated_storage <= 65536
    error_message = "RDS allocated storage must be between 20 and 65536 GB."
  }
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "rds_db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "salesdb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.rds_db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "rds_username" {
  description = "Master username for RDS instance"
  type        = string
  default     = "postgres"
  
  validation {
    condition     = length(var.rds_username) >= 1 && length(var.rds_username) <= 63
    error_message = "RDS username must be between 1 and 63 characters."
  }
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access RDS instance"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}

variable "quicksight_user_identity_type" {
  description = "Identity type for QuickSight user (IAM or QUICKSIGHT)"
  type        = string
  default     = "IAM"
  
  validation {
    condition     = contains(["IAM", "QUICKSIGHT"], var.quicksight_user_identity_type)
    error_message = "QuickSight user identity type must be IAM or QUICKSIGHT."
  }
}

variable "quicksight_user_role" {
  description = "Role for QuickSight user (ADMIN, AUTHOR, or READER)"
  type        = string
  default     = "AUTHOR"
  
  validation {
    condition     = contains(["ADMIN", "AUTHOR", "READER"], var.quicksight_user_role)
    error_message = "QuickSight user role must be ADMIN, AUTHOR, or READER."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}