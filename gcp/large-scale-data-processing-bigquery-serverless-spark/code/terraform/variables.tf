# ==============================================================================
# TERRAFORM VARIABLES FOR BIGQUERY SERVERLESS SPARK DATA PROCESSING
# ==============================================================================
# This file defines all configurable variables for the BigQuery Serverless
# Spark data processing infrastructure. Variables are organized by resource
# type and include validation rules, descriptions, and sensible defaults.
# ==============================================================================

# ==============================================================================
# PROJECT AND LOCATION VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (BigQuery datasets, Cloud Storage buckets)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (if needed for compute instances)"
  type        = string
  default     = "us-central1-a"
}

# ==============================================================================
# CLOUD STORAGE VARIABLES
# ==============================================================================

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (suffix will be auto-generated for uniqueness)"
  type        = string
  default     = "data-lake-spark"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the Cloud Storage bucket for data protection"
  type        = bool
  default     = true
}

variable "lifecycle_transition_days" {
  description = "Number of days after which objects transition to Nearline storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_days >= 1 && var.lifecycle_transition_days <= 365
    error_message = "Lifecycle transition days must be between 1 and 365."
  }
}

variable "lifecycle_deletion_days" {
  description = "Number of days after which objects are deleted (0 to disable deletion)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_deletion_days >= 0 && var.lifecycle_deletion_days <= 3650
    error_message = "Lifecycle deletion days must be between 0 and 3650 (10 years)."
  }
}

# ==============================================================================
# BIGQUERY VARIABLES
# ==============================================================================

variable "dataset_name_prefix" {
  description = "Prefix for the BigQuery dataset name (suffix will be auto-generated for uniqueness)"
  type        = string
  default     = "analytics_dataset"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name_prefix))
    error_message = "Dataset name prefix must contain only letters, numbers, and underscores."
  }
}

variable "dataset_owner_email" {
  description = "Email address of the dataset owner (must be a valid Google account)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.dataset_owner_email))
    error_message = "Dataset owner email must be a valid email address."
  }
}

variable "table_expiration_days" {
  description = "Default table expiration in days (0 for no expiration)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.table_expiration_days >= 0 && var.table_expiration_days <= 3650
    error_message = "Table expiration days must be between 0 and 3650 (10 years)."
  }
}

variable "enable_dataset_deletion" {
  description = "Allow deletion of dataset contents on terraform destroy (use with caution in production)"
  type        = bool
  default     = false
}

variable "enable_table_deletion_protection" {
  description = "Enable deletion protection for BigQuery tables"
  type        = bool
  default     = true
}

# ==============================================================================
# IAM AND SECURITY VARIABLES
# ==============================================================================

variable "service_account_prefix" {
  description = "Prefix for the Serverless Spark service account name"
  type        = string
  default     = "spark-processor"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_prefix))
    error_message = "Service account prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "network_tags" {
  description = "Network tags to apply to Dataproc Serverless jobs for firewall rules"
  type        = list(string)
  default     = ["spark-processing"]
  
  validation {
    condition     = length(var.network_tags) <= 10
    error_message = "Maximum of 10 network tags are allowed."
  }
}

# ==============================================================================
# DATAPROC SERVERLESS VARIABLES
# ==============================================================================

variable "batch_job_prefix" {
  description = "Prefix for Dataproc Serverless batch job names"
  type        = string
  default     = "spark-analytics-job"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.batch_job_prefix))
    error_message = "Batch job prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "batch_job_ttl" {
  description = "Time-to-live for Dataproc Serverless batch jobs (in seconds)"
  type        = string
  default     = "1800s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.batch_job_ttl))
    error_message = "Batch job TTL must be in seconds format (e.g., '1800s')."
  }
}

variable "create_sample_batch" {
  description = "Create a sample Dataproc Serverless batch job for demonstration"
  type        = bool
  default     = false
}

variable "spark_executor_instances" {
  description = "Number of Spark executor instances (auto for dynamic allocation)"
  type        = string
  default     = "2"
  
  validation {
    condition     = var.spark_executor_instances == "auto" || can(tonumber(var.spark_executor_instances))
    error_message = "Spark executor instances must be 'auto' or a valid number."
  }
}

variable "spark_executor_memory" {
  description = "Memory allocation per Spark executor (e.g., '4g', '8g')"
  type        = string
  default     = "4g"
  
  validation {
    condition     = can(regex("^[0-9]+[gm]$", var.spark_executor_memory))
    error_message = "Spark executor memory must be in format like '4g' or '2048m'."
  }
}

variable "spark_executor_cores" {
  description = "Number of CPU cores per Spark executor"
  type        = number
  default     = 2
  
  validation {
    condition     = var.spark_executor_cores >= 1 && var.spark_executor_cores <= 16
    error_message = "Spark executor cores must be between 1 and 16."
  }
}

# ==============================================================================
# MONITORING AND ALERTING VARIABLES
# ==============================================================================

variable "create_monitoring_dashboard" {
  description = "Create a Cloud Monitoring dashboard for Spark job monitoring"
  type        = bool
  default     = true
}

variable "create_log_metrics" {
  description = "Create log-based metrics for Spark job monitoring"
  type        = bool
  default     = true
}

variable "create_alerts" {
  description = "Create alerting policies for Spark job failures"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for alerting notifications (empty to disable email notifications)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# ==============================================================================
# RESOURCE LABELING VARIABLES
# ==============================================================================

variable "labels" {
  description = "A map of labels to apply to all resources for organization and billing"
  type        = map(string)
  default = {
    environment = "development"
    project     = "bigquery-serverless-spark"
    owner       = "data-engineering"
    cost-center = "analytics"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9-_]*[a-z0-9]$", key)) &&
      can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", value))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

# ==============================================================================
# ADVANCED CONFIGURATION VARIABLES
# ==============================================================================

variable "enable_private_google_access" {
  description = "Enable Private Google Access for Dataproc Serverless jobs"
  type        = bool
  default     = false
}

variable "custom_spark_properties" {
  description = "Additional Spark configuration properties as key-value pairs"
  type        = map(string)
  default = {
    "spark.sql.adaptive.enabled"                   = "true"
    "spark.sql.adaptive.coalescePartitions.enabled" = "true"
    "spark.dynamicAllocation.enabled"              = "true"
    "spark.dynamicAllocation.minExecutors"         = "1"
    "spark.dynamicAllocation.maxExecutors"         = "10"
  }
}

variable "bigquery_connector_version" {
  description = "Version of the BigQuery Spark connector to use"
  type        = string
  default     = "0.36.1"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.bigquery_connector_version))
    error_message = "BigQuery connector version must be in semantic version format (e.g., '0.36.1')."
  }
}

variable "spark_runtime_version" {
  description = "Dataproc Serverless runtime version for Spark"
  type        = string
  default     = "2.2"
  
  validation {
    condition = contains([
      "2.0", "2.1", "2.2"
    ], var.spark_runtime_version)
    error_message = "Spark runtime version must be a supported Dataproc Serverless version."
  }
}

# ==============================================================================
# DATA PROCESSING VARIABLES
# ==============================================================================

variable "sample_data_size" {
  description = "Size of sample data to generate (small, medium, large)"
  type        = string
  default     = "small"
  
  validation {
    condition = contains([
      "small", "medium", "large"
    ], var.sample_data_size)
    error_message = "Sample data size must be 'small', 'medium', or 'large'."
  }
}

variable "enable_data_lineage" {
  description = "Enable data lineage tracking for Spark jobs"
  type        = bool
  default     = false
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features (preemptible instances, auto-scaling)"
  type        = bool
  default     = true
}

# ==============================================================================
# DEVELOPMENT AND TESTING VARIABLES
# ==============================================================================

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production"
    ], var.environment)
    error_message = "Environment must be 'development', 'staging', or 'production'."
  }
}

variable "enable_debug_logging" {
  description = "Enable debug-level logging for Spark jobs"
  type        = bool
  default     = false
}

variable "terraform_workspace" {
  description = "Terraform workspace name for state isolation"
  type        = string
  default     = "default"
}