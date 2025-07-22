# Input variables for the Lake Formation Fine-Grained Access Control infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "data_lake_admin_arn" {
  description = "ARN of the IAM user or role to be designated as Lake Formation data lake administrator"
  type        = string
  default     = ""
  
  validation {
    condition = var.data_lake_admin_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+", var.data_lake_admin_arn))
    error_message = "Data lake admin ARN must be a valid IAM user or role ARN, or empty to use current caller identity."
  }
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added for uniqueness"
  type        = string
  default     = "data-lake-fgac"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_name" {
  description = "Name of the Glue database to create"
  type        = string
  default     = "sample_database"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.database_name))
    error_message = "Database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "table_name" {
  description = "Name of the Glue table to create"
  type        = string
  default     = "customer_data"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.table_name))
    error_message = "Table name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for Lake Formation audit trail"
  type        = bool
  default     = true
}

variable "data_analyst_role_name" {
  description = "Name for the data analyst IAM role"
  type        = string
  default     = "DataAnalystRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.data_analyst_role_name))
    error_message = "Role name must be a valid IAM role name."
  }
}

variable "finance_team_role_name" {
  description = "Name for the finance team IAM role"
  type        = string
  default     = "FinanceTeamRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.finance_team_role_name))
    error_message = "Role name must be a valid IAM role name."
  }
}

variable "hr_role_name" {
  description = "Name for the HR IAM role"
  type        = string
  default     = "HRRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.hr_role_name))
    error_message = "Role name must be a valid IAM role name."
  }
}

variable "create_sample_data" {
  description = "Whether to create and upload sample data to the S3 bucket"
  type        = bool
  default     = true
}

variable "row_level_filter_expression" {
  description = "Row-level filter expression for data cells filter"
  type        = string
  default     = "department = \"Engineering\""
  
  validation {
    condition     = length(var.row_level_filter_expression) > 0
    error_message = "Row-level filter expression cannot be empty."
  }
}