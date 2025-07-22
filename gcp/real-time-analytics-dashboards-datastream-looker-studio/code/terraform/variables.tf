# Variables for Real-Time Analytics Dashboards with Datastream and Looker Studio
# These variables configure the entire real-time analytics pipeline infrastructure

# Project and Location Configuration
variable "project_id" {
  type        = string
  description = "The Google Cloud project ID where resources will be created"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  type        = string
  description = "The Google Cloud region for resources (e.g., us-central1, europe-west1)"
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for labeling and naming resources"
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production", "demo"], var.environment)
    error_message = "Environment must be one of: development, staging, production, demo."
  }
}

# BigQuery Configuration
variable "dataset_name" {
  type        = string
  description = "Name of the BigQuery dataset for analytics data"
  default     = "ecommerce_analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "table_expiration_ms" {
  type        = number
  description = "Default table expiration time in milliseconds (null for no expiration)"
  default     = null
}

variable "enable_dataset_deletion" {
  type        = bool
  description = "Enable deletion of non-empty dataset during terraform destroy"
  default     = false
}

variable "kms_key_name" {
  type        = string
  description = "KMS key name for BigQuery dataset encryption (optional)"
  default     = null
}

# Datastream Configuration
variable "stream_name" {
  type        = string
  description = "Name for the Datastream stream"
  default     = "analytics-stream"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.stream_name))
    error_message = "Stream name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "source_connection_name" {
  type        = string
  description = "Name for the source database connection profile"
  default     = "source-db-connection"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.source_connection_name))
    error_message = "Connection name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "bigquery_connection_name" {
  type        = string
  description = "Name for the BigQuery destination connection profile"
  default     = "bigquery-destination"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.bigquery_connection_name))
    error_message = "Connection name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "data_freshness_seconds" {
  type        = number
  description = "Maximum data freshness in seconds for BigQuery destination"
  default     = 300
  
  validation {
    condition     = var.data_freshness_seconds >= 60 && var.data_freshness_seconds <= 3600
    error_message = "Data freshness must be between 60 and 3600 seconds."
  }
}

# Source Database Configuration
variable "source_db_type" {
  type        = string
  description = "Type of source database (mysql, postgresql, oracle)"
  default     = "mysql"
  
  validation {
    condition     = contains(["mysql", "postgresql", "oracle"], var.source_db_type)
    error_message = "Source database type must be one of: mysql, postgresql, oracle."
  }
}

variable "source_db_hostname" {
  type        = string
  description = "Hostname or IP address of the source database"
  
  validation {
    condition     = length(var.source_db_hostname) > 0
    error_message = "Source database hostname cannot be empty."
  }
}

variable "source_db_port" {
  type        = number
  description = "Port number for the source database connection"
  default     = 3306
  
  validation {
    condition     = var.source_db_port > 0 && var.source_db_port <= 65535
    error_message = "Database port must be between 1 and 65535."
  }
}

variable "source_db_username" {
  type        = string
  description = "Username for connecting to the source database"
  
  validation {
    condition     = length(var.source_db_username) > 0
    error_message = "Database username cannot be empty."
  }
}

variable "source_db_password" {
  type        = string
  description = "Password for connecting to the source database"
  sensitive   = true
  
  validation {
    condition     = length(var.source_db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "source_db_name" {
  type        = string
  description = "Database name for PostgreSQL connections"
  default     = null
}

# SSL Configuration for Database Connections
variable "ssl_client_certificate" {
  type        = string
  description = "SSL client certificate for secure database connections (optional)"
  default     = null
  sensitive   = true
}

variable "ssl_client_key" {
  type        = string
  description = "SSL client private key for secure database connections (optional)"
  default     = null
  sensitive   = true
}

variable "ssl_ca_certificate" {
  type        = string
  description = "SSL CA certificate for validating server certificates (optional)"
  default     = null
  sensitive   = true
}

# Oracle-specific Configuration
variable "oracle_database_service" {
  type        = string
  description = "Oracle database service name"
  default     = null
}

variable "oracle_connection_attributes" {
  type        = map(string)
  description = "Additional connection attributes for Oracle database"
  default     = {}
}

# PostgreSQL-specific Configuration
variable "postgresql_publication" {
  type        = string
  description = "PostgreSQL logical replication publication name"
  default     = "datastream_publication"
}

variable "postgresql_replication_slot" {
  type        = string
  description = "PostgreSQL logical replication slot name"
  default     = "datastream_slot"
}

# Datastream Performance Configuration
variable "max_concurrent_cdc_tasks" {
  type        = number
  description = "Maximum number of concurrent CDC tasks for Datastream"
  default     = 5
  
  validation {
    condition     = var.max_concurrent_cdc_tasks >= 1 && var.max_concurrent_cdc_tasks <= 50
    error_message = "Max concurrent CDC tasks must be between 1 and 50."
  }
}

variable "max_concurrent_backfill_tasks" {
  type        = number
  description = "Maximum number of concurrent backfill tasks for Datastream"
  default     = 12
  
  validation {
    condition     = var.max_concurrent_backfill_tasks >= 1 && var.max_concurrent_backfill_tasks <= 50
    error_message = "Max concurrent backfill tasks must be between 1 and 50."
  }
}

# Table Selection Configuration
variable "include_tables" {
  type = list(object({
    database = optional(string)
    schema   = optional(string)
    tables = list(object({
      table_name = string
      columns = optional(list(object({
        column_name = string
        data_type   = optional(string)
        nullable    = optional(bool)
      })))
    }))
  }))
  description = "List of tables to include in replication with optional column filtering"
  default = [
    {
      database = "ecommerce"
      tables = [
        {
          table_name = "sales_orders"
          columns = null
        },
        {
          table_name = "customers"
          columns = null
        },
        {
          table_name = "products"
          columns = null
        }
      ]
    }
  ]
}

variable "exclude_tables" {
  type = list(object({
    database = optional(string)
    schema   = optional(string)
    tables   = list(string)
  }))
  description = "List of tables to exclude from replication"
  default     = []
}

# BigQuery Dataset Access Control
variable "dataset_access_roles" {
  type = list(object({
    role       = string
    user_email = string
  }))
  description = "List of IAM roles and users for BigQuery dataset access"
  default     = []
}

# Looker Studio Configuration
variable "looker_studio_users" {
  type        = list(string)
  description = "List of user emails who will access Looker Studio dashboards"
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.looker_studio_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All Looker Studio user entries must be valid email addresses."
  }
}

# BI Engine Configuration for Performance
variable "enable_bi_engine" {
  type        = bool
  description = "Enable BigQuery BI Engine for faster dashboard performance"
  default     = false
}

variable "bi_engine_size" {
  type        = number
  description = "BI Engine reservation size in MB (minimum 1000MB)"
  default     = 1000
  
  validation {
    condition     = var.bi_engine_size >= 1000
    error_message = "BI Engine size must be at least 1000 MB."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  type        = bool
  description = "Enable monitoring and alerting for the analytics pipeline"
  default     = true
}

variable "alert_notification_channels" {
  type        = list(string)
  description = "List of notification channel IDs for monitoring alerts"
  default     = []
}

# Cost Management Configuration
variable "enable_cost_controls" {
  type        = bool
  description = "Enable cost control measures like query slot limits"
  default     = true
}

variable "daily_query_quota_gb" {
  type        = number
  description = "Daily BigQuery query quota in GB (null for unlimited)"
  default     = null
}

# Data Retention Configuration
variable "data_retention_days" {
  type        = number
  description = "Number of days to retain data in BigQuery tables"
  default     = 365
  
  validation {
    condition     = var.data_retention_days > 0
    error_message = "Data retention days must be greater than 0."
  }
}

# Network Security Configuration
variable "enable_private_google_access" {
  type        = bool
  description = "Enable private Google access for secure connections"
  default     = true
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "List of IP ranges allowed to access the analytics resources"
  default     = []
}

# Backup and Disaster Recovery Configuration
variable "enable_backup" {
  type        = bool
  description = "Enable automated backups for BigQuery datasets"
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Performance Tuning Configuration
variable "enable_clustering" {
  type        = bool
  description = "Enable table clustering for better query performance"
  default     = true
}

variable "clustering_fields" {
  type        = list(string)
  description = "Fields to use for table clustering"
  default     = ["order_date", "customer_id"]
}

variable "enable_partitioning" {
  type        = bool
  description = "Enable table partitioning for better performance and cost management"
  default     = true
}

variable "partition_field" {
  type        = string
  description = "Field to use for table partitioning (typically a date field)"
  default     = "order_date"
}

# Compliance and Security Configuration
variable "enable_audit_logging" {
  type        = bool
  description = "Enable audit logging for compliance requirements"
  default     = true
}

variable "enable_data_classification" {
  type        = bool
  description = "Enable automatic data classification and labeling"
  default     = false
}

variable "enable_column_level_security" {
  type        = bool
  description = "Enable column-level security for sensitive data"
  default     = false
}

# Development and Testing Configuration
variable "enable_debug_logging" {
  type        = bool
  description = "Enable debug logging for troubleshooting"
  default     = false
}

variable "create_sample_data" {
  type        = bool
  description = "Create sample data for testing and development"
  default     = false
}

# Resource Tagging Configuration
variable "additional_labels" {
  type        = map(string)
  description = "Additional labels to apply to all resources"
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}