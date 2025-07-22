# =============================================================================
# Variables for Advanced Data Lake Governance Infrastructure
# =============================================================================
# This file defines all configurable parameters for the data lake governance
# platform, enabling customization for different environments and requirements.

# =============================================================================
# GENERAL CONFIGURATION
# =============================================================================

variable "environment" {
  description = "Environment name for resource tagging and configuration"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production", "test"], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness and organization"
  type        = string
  default     = "enterprise-data-gov"
  
  validation {
    condition     = length(var.resource_prefix) <= 20 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = null
  
  validation {
    condition = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1' or 'eu-west-1'."
  }
}

# =============================================================================
# DATA LAKE STORAGE CONFIGURATION
# =============================================================================

variable "data_lake_bucket_prefix" {
  description = "Prefix for the S3 data lake bucket name (will be combined with random suffix)"
  type        = string
  default     = "enterprise-datalake"
  
  validation {
    condition     = length(var.data_lake_bucket_prefix) <= 40 && can(regex("^[a-z0-9-]+$", var.data_lake_bucket_prefix))
    error_message = "Bucket prefix must be 40 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "raw_data_prefix" {
  description = "S3 prefix for raw data zone in the data lake"
  type        = string
  default     = "raw-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-/]+$", var.raw_data_prefix))
    error_message = "Raw data prefix must contain only lowercase letters, numbers, hyphens, and forward slashes."
  }
}

variable "curated_data_prefix" {
  description = "S3 prefix for curated data zone in the data lake"
  type        = string
  default     = "curated-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-/]+$", var.curated_data_prefix))
    error_message = "Curated data prefix must contain only lowercase letters, numbers, hyphens, and forward slashes."
  }
}

variable "analytics_data_prefix" {
  description = "S3 prefix for analytics-ready data zone in the data lake"
  type        = string
  default     = "analytics-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-/]+$", var.analytics_data_prefix))
    error_message = "Analytics data prefix must contain only lowercase letters, numbers, hyphens, and forward slashes."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning for data protection and audit compliance"
  type        = bool
  default     = true
}

variable "s3_encryption_type" {
  description = "S3 server-side encryption type for data at rest"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_type)
    error_message = "S3 encryption type must be either 'AES256' or 'aws:kms'."
  }
}

# =============================================================================
# GLUE DATA CATALOG CONFIGURATION
# =============================================================================

variable "glue_database_name" {
  description = "Name of the AWS Glue database for the enterprise data catalog"
  type        = string
  default     = "enterprise_data_catalog"
  
  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.glue_database_name)) && length(var.glue_database_name) <= 255
    error_message = "Glue database name must contain only lowercase letters, numbers, and underscores, and be 255 characters or less."
  }
}

variable "glue_job_max_capacity" {
  description = "Maximum number of AWS Glue data processing units (DPUs) for ETL jobs"
  type        = number
  default     = 2.0
  
  validation {
    condition     = var.glue_job_max_capacity >= 0.0625 && var.glue_job_max_capacity <= 100
    error_message = "Glue job max capacity must be between 0.0625 and 100 DPUs."
  }
}

variable "glue_job_timeout" {
  description = "Timeout in minutes for Glue ETL jobs"
  type        = number
  default     = 60
  
  validation {
    condition     = var.glue_job_timeout >= 1 && var.glue_job_timeout <= 2880
    error_message = "Glue job timeout must be between 1 and 2880 minutes (48 hours)."
  }
}

variable "glue_version" {
  description = "AWS Glue version for ETL jobs"
  type        = string
  default     = "4.0"
  
  validation {
    condition     = contains(["2.0", "3.0", "4.0"], var.glue_version)
    error_message = "Glue version must be one of: 2.0, 3.0, 4.0."
  }
}

# =============================================================================
# LAKE FORMATION CONFIGURATION
# =============================================================================

variable "enable_external_data_filtering" {
  description = "Enable external data filtering in Lake Formation for cross-account data sharing"
  type        = bool
  default     = true
}

variable "trusted_resource_owners" {
  description = "List of AWS account IDs trusted for cross-account data sharing"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for account_id in var.trusted_resource_owners : can(regex("^[0-9]{12}$", account_id))
    ])
    error_message = "All trusted resource owners must be valid 12-digit AWS account IDs."
  }
}

variable "lake_formation_admins" {
  description = "List of IAM principals to grant Lake Formation admin permissions"
  type        = list(string)
  default     = []
}

# =============================================================================
# DATAZONE CONFIGURATION
# =============================================================================

variable "datazone_domain_name" {
  description = "Name for the Amazon DataZone domain"
  type        = string
  default     = "enterprise-data-governance"
  
  validation {
    condition     = length(var.datazone_domain_name) >= 1 && length(var.datazone_domain_name) <= 64
    error_message = "DataZone domain name must be between 1 and 64 characters."
  }
}

variable "enable_datazone_glossary" {
  description = "Enable creation of business glossary in DataZone"
  type        = bool
  default     = true
}

variable "datazone_project_name" {
  description = "Name for the DataZone analytics project"
  type        = string
  default     = "Customer Analytics Project"
  
  validation {
    condition     = length(var.datazone_project_name) >= 1 && length(var.datazone_project_name) <= 64
    error_message = "DataZone project name must be between 1 and 64 characters."
  }
}

# =============================================================================
# DATA GOVERNANCE AND SECURITY
# =============================================================================

variable "enable_pii_data_filter" {
  description = "Enable data cell filters for PII protection in customer data"
  type        = bool
  default     = true
}

variable "allowed_customer_segments" {
  description = "List of customer segments allowed through data filters"
  type        = list(string)
  default     = ["premium", "standard"]
  
  validation {
    condition = alltrue([
      for segment in var.allowed_customer_segments : can(regex("^[a-z]+$", segment))
    ])
    error_message = "Customer segments must contain only lowercase letters."
  }
}

variable "pii_columns_excluded" {
  description = "List of PII columns to exclude from analyst access"
  type        = list(string)
  default     = ["first_name", "last_name", "email", "phone"]
}

variable "non_pii_columns_included" {
  description = "List of non-PII columns to include in filtered data access"
  type        = list(string)
  default     = ["customer_id", "registration_date", "customer_segment", "lifetime_value", "region"]
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid AWS retention period."
  }
}

variable "enable_etl_failure_alerts" {
  description = "Enable CloudWatch alarms for ETL job failures"
  type        = bool
  default     = true
}

variable "etl_failure_threshold" {
  description = "Number of ETL failures before triggering alarm"
  type        = number
  default     = 1
  
  validation {
    condition     = var.etl_failure_threshold >= 1 && var.etl_failure_threshold <= 10
    error_message = "ETL failure threshold must be between 1 and 10."
  }
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

# =============================================================================
# SAMPLE DATA CONFIGURATION
# =============================================================================

variable "create_sample_data" {
  description = "Create sample data files for testing and validation"
  type        = bool
  default     = true
}

variable "sample_customer_count" {
  description = "Number of sample customer records to generate"
  type        = number
  default     = 10
  
  validation {
    condition     = var.sample_customer_count >= 0 && var.sample_customer_count <= 1000
    error_message = "Sample customer count must be between 0 and 1000."
  }
}

variable "sample_transaction_count" {
  description = "Number of sample transaction records to generate"
  type        = number
  default     = 20
  
  validation {
    condition     = var.sample_transaction_count >= 0 && var.sample_transaction_count <= 10000
    error_message = "Sample transaction count must be between 0 and 10000."
  }
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "enable_cross_account_sharing" {
  description = "Enable Lake Formation cross-account data sharing capabilities"
  type        = bool
  default     = false
}

variable "enable_data_lineage_tracking" {
  description = "Enable comprehensive data lineage tracking in ETL jobs"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like S3 Intelligent Tiering"
  type        = bool
  default     = true
}

variable "compliance_mode" {
  description = "Compliance mode for additional security and audit features"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["basic", "standard", "strict"], var.compliance_mode)
    error_message = "Compliance mode must be one of: basic, standard, strict."
  }
}

# =============================================================================
# RESOURCE TAGS
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9\\s\\-_.:/=+@]*$", key)) && can(regex("^[a-zA-Z0-9\\s\\-_.:/=+@]*$", value))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, and these special characters: - _ . : / = + @"
  }
}