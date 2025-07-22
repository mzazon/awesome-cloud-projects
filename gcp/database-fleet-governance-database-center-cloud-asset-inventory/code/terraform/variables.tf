# variables.tf - Input Variables for Database Fleet Governance
# Configuration variables for Database Center and Cloud Asset Inventory solution

variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "organization_id" {
  description = "GCP Organization ID for organization-level asset feeds (optional)"
  type        = string
  default     = null
}

variable "folder_id" {
  description = "GCP Folder ID for folder-level asset feeds (optional)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "db-governance"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

# Database Fleet Configuration
variable "create_sample_databases" {
  description = "Whether to create sample database instances for testing governance policies"
  type        = bool
  default     = true
}

variable "cloudsql_instance_tier" {
  description = "Cloud SQL instance tier for sample database"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2",
      "db-n1-standard-4", "db-n1-highmem-2", "db-n1-highmem-4"
    ], var.cloudsql_instance_tier)
    error_message = "Cloud SQL instance tier must be a valid tier."
  }
}

variable "cloudsql_database_version" {
  description = "Cloud SQL database version"
  type        = string
  default     = "POSTGRES_15"
  
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16",
      "MYSQL_8_0", "MYSQL_8_0_18", "MYSQL_8_0_26", "MYSQL_8_0_27",
      "SQLSERVER_2019_STANDARD", "SQLSERVER_2019_ENTERPRISE"
    ], var.cloudsql_database_version)
    error_message = "Database version must be a supported Cloud SQL version."
  }
}

variable "spanner_instance_config" {
  description = "Spanner instance configuration"
  type        = string
  default     = "regional-us-central1"
  
  validation {
    condition = can(regex("^(regional|multi-regional)-", var.spanner_instance_config))
    error_message = "Spanner instance config must be a valid configuration."
  }
}

variable "spanner_processing_units" {
  description = "Number of processing units for Spanner instance"
  type        = number
  default     = 100
  
  validation {
    condition     = var.spanner_processing_units >= 100 && var.spanner_processing_units <= 2000
    error_message = "Spanner processing units must be between 100 and 2000."
  }
}

variable "bigtable_cluster_num_nodes" {
  description = "Number of nodes in Bigtable cluster"
  type        = number
  default     = 1
  
  validation {
    condition     = var.bigtable_cluster_num_nodes >= 1 && var.bigtable_cluster_num_nodes <= 30
    error_message = "Bigtable cluster nodes must be between 1 and 30."
  }
}

variable "bigtable_instance_type" {
  description = "Bigtable instance type"
  type        = string
  default     = "DEVELOPMENT"
  
  validation {
    condition = contains(["DEVELOPMENT", "PRODUCTION"], var.bigtable_instance_type)
    error_message = "Bigtable instance type must be DEVELOPMENT or PRODUCTION."
  }
}

# Governance Configuration
variable "enable_asset_inventory_export" {
  description = "Whether to enable Cloud Asset Inventory exports to BigQuery"
  type        = bool
  default     = true
}

variable "asset_export_schedule" {
  description = "Cron schedule for automated asset exports"
  type        = string
  default     = "0 */6 * * *" # Every 6 hours
  
  validation {
    condition = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.asset_export_schedule))
    error_message = "Asset export schedule must be a valid cron expression."
  }
}

variable "compliance_report_schedule" {
  description = "Cron schedule for compliance report generation"
  type        = string
  default     = "0 8 * * *" # Daily at 8 AM
  
  validation {
    condition = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.compliance_report_schedule))
    error_message = "Compliance report schedule must be a valid cron expression."
  }
}

variable "governance_workflow_timeout" {
  description = "Timeout for governance workflows in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.governance_workflow_timeout >= 60 && var.governance_workflow_timeout <= 3600
    error_message = "Workflow timeout must be between 60 and 3600 seconds."
  }
}

# Monitoring and Alerting Configuration
variable "alert_email_addresses" {
  description = "List of email addresses for governance alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "enable_dashboard" {
  description = "Whether to create a custom monitoring dashboard"
  type        = bool
  default     = true
}

variable "compliance_threshold" {
  description = "Minimum compliance score threshold for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.compliance_threshold >= 0.0 && var.compliance_threshold <= 1.0
    error_message = "Compliance threshold must be between 0.0 and 1.0."
  }
}

# Storage Configuration
variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  
  validation {
    condition = contains(["US", "EU", "us-central1", "europe-west1", "asia-east1"], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid location."
  }
}

variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  
  validation {
    condition = contains(["US", "EU", "ASIA"], var.storage_bucket_location)
    error_message = "Storage bucket location must be US, EU, or ASIA."
  }
}

variable "storage_bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logs for database governance activities"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    solution   = "database-governance"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", key))
    ])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, and end with a letter or number."
  }
}