# Variables for Lake Formation cross-account data access infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "lake-formation-cross-account"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "consumer_account_id" {
  description = "AWS Account ID of the consumer account for cross-account sharing"
  type        = string

  validation {
    condition = can(regex("^[0-9]{12}$", var.consumer_account_id))
    error_message = "Consumer account ID must be a valid 12-digit AWS account ID."
  }
}

variable "consumer_account_assume_role_arn" {
  description = "ARN of the role to assume in the consumer account for resource creation"
  type        = string
  default     = null

  validation {
    condition = var.consumer_account_assume_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.consumer_account_assume_role_arn))
    error_message = "Consumer account assume role ARN must be a valid IAM role ARN or null."
  }
}

variable "data_lake_bucket_name" {
  description = "Name for the S3 data lake bucket (will be made unique with random suffix)"
  type        = string
  default     = "data-lake"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.data_lake_bucket_name))
    error_message = "Data lake bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 data lake bucket for data governance"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption on the S3 data lake bucket"
  type        = bool
  default     = true
}

variable "lf_tag_values" {
  description = "Configuration for Lake Formation tags and their allowed values"
  type = object({
    department = list(string)
    classification = list(string)
    data_category = list(string)
  })
  default = {
    department = ["finance", "marketing", "engineering", "hr"]
    classification = ["public", "internal", "confidential", "restricted"]
    data_category = ["financial", "customer", "operational", "analytics"]
  }

  validation {
    condition = length(var.lf_tag_values.department) > 0 && length(var.lf_tag_values.classification) > 0 && length(var.lf_tag_values.data_category) > 0
    error_message = "All LF-Tag categories must have at least one value."
  }
}

variable "database_configurations" {
  description = "Configuration for Glue databases to be created"
  type = map(object({
    description = string
    lf_tags = map(list(string))
  }))
  default = {
    financial_db = {
      description = "Financial reporting database"
      lf_tags = {
        department = ["finance"]
        classification = ["confidential"]
        data_category = ["financial"]
      }
    }
    customer_db = {
      description = "Customer information database"
      lf_tags = {
        department = ["marketing"]
        classification = ["internal"]
        data_category = ["customer"]
      }
    }
  }
}

variable "shared_databases" {
  description = "List of database names to share with the consumer account"
  type        = list(string)
  default     = ["financial_db"]

  validation {
    condition = length(var.shared_databases) > 0
    error_message = "At least one database must be specified for sharing."
  }
}

variable "cross_account_permissions" {
  description = "LF-Tag based permissions to grant to the consumer account"
  type = map(object({
    tag_key = string
    tag_values = list(string)
    permissions = list(string)
    permissions_with_grant_option = list(string)
  }))
  default = {
    finance_access = {
      tag_key = "department"
      tag_values = ["finance"]
      permissions = ["ASSOCIATE", "DESCRIBE"]
      permissions_with_grant_option = ["ASSOCIATE"]
    }
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for Lake Formation API calls"
  type        = bool
  default     = true
}

variable "enable_consumer_account_setup" {
  description = "Enable automatic setup of consumer account resources (requires assume role)"
  type        = bool
  default     = false
}

variable "data_analyst_role_name" {
  description = "Name for the data analyst role in the consumer account"
  type        = string
  default     = "DataAnalystRole"

  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_+=,.@-]*$", var.data_analyst_role_name))
    error_message = "Data analyst role name must be a valid IAM role name."
  }
}

variable "glue_crawler_configurations" {
  description = "Configuration for Glue crawlers to discover data schemas"
  type = map(object({
    database_name = string
    s3_path = string
    description = string
    schedule = string
  }))
  default = {
    financial_reports_crawler = {
      database_name = "financial_db"
      s3_path = "financial-reports/"
      description = "Crawler for financial reports data"
      schedule = "cron(0 6 * * ? *)"  # Daily at 6 AM
    }
    customer_data_crawler = {
      database_name = "customer_db"
      s3_path = "customer-data/"
      description = "Crawler for customer data"
      schedule = "cron(0 7 * * ? *)"  # Daily at 7 AM
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}