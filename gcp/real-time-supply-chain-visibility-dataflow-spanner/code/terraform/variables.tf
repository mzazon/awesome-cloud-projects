# ============================================================================
# Variables for Real-Time Supply Chain Visibility Infrastructure
# ============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid GCP region name (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid GCP zone name (e.g., us-central1-a, europe-west1-b)."
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

# ============================================================================
# Cloud Spanner Configuration
# ============================================================================

variable "spanner_instance_config" {
  description = "The configuration for the Spanner instance"
  type        = string
  default     = "regional-us-central1"
  validation {
    condition     = can(regex("^(regional|multi-regional)-", var.spanner_instance_config))
    error_message = "Spanner instance config must be a valid configuration (e.g., regional-us-central1, multi-regional-us)."
  }
}

variable "spanner_node_count" {
  description = "Number of nodes for the Spanner instance"
  type        = number
  default     = 1
  validation {
    condition     = var.spanner_node_count >= 1 && var.spanner_node_count <= 100
    error_message = "Spanner node count must be between 1 and 100."
  }
}

variable "spanner_processing_units" {
  description = "Number of processing units for the Spanner instance (alternative to node_count)"
  type        = number
  default     = null
  validation {
    condition     = var.spanner_processing_units == null || (var.spanner_processing_units >= 100 && var.spanner_processing_units <= 100000)
    error_message = "Spanner processing units must be between 100 and 100000, or null to use node count."
  }
}

variable "spanner_edition" {
  description = "The edition of the Spanner instance"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "ENTERPRISE", "ENTERPRISE_PLUS"], var.spanner_edition)
    error_message = "Spanner edition must be one of: STANDARD, ENTERPRISE, ENTERPRISE_PLUS."
  }
}

variable "spanner_database_name" {
  description = "Name of the Spanner database"
  type        = string
  default     = "supply-chain-db"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){0,28}[a-z0-9]$", var.spanner_database_name))
    error_message = "Database name must be 1-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# ============================================================================
# Cloud Pub/Sub Configuration
# ============================================================================

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for logistics events"
  type        = string
  default     = "logistics-events"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-_]){0,254}$", var.pubsub_topic_name))
    error_message = "Topic name must be 1-255 characters, start with a letter, and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for Dataflow processing"
  type        = string
  default     = "logistics-events-sub"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-_]){0,254}$", var.pubsub_subscription_name))
    error_message = "Subscription name must be 1-255 characters, start with a letter, and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "pubsub_message_retention_duration" {
  description = "How long to retain unacknowledged messages in the subscription"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "The acknowledgment deadline for messages in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# ============================================================================
# BigQuery Configuration
# ============================================================================

variable "bigquery_dataset_name" {
  description = "Name of the BigQuery dataset for analytics"
  type        = string
  default     = "supply_chain_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.bigquery_dataset_name))
    error_message = "Dataset name must be 1-1024 characters and contain only letters, numbers, and underscores."
  }
}

variable "bigquery_dataset_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "us-central1", "europe-west1", "asia-southeast1"], var.bigquery_dataset_location)
    error_message = "Dataset location must be a valid BigQuery location (US, EU, or a specific region)."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Number of days before BigQuery tables expire (0 = no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.bigquery_table_expiration_days >= 0
    error_message = "Table expiration days must be non-negative (0 means no expiration)."
  }
}

# ============================================================================
# Cloud Storage Configuration
# ============================================================================

variable "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for Dataflow staging (will be prefixed with project ID)"
  type        = string
  default     = "supply-chain-dataflow"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]){1,61}[a-z0-9]$", var.storage_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start and end with lowercase letters or numbers, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US-CENTRAL1"
  validation {
    condition     = can(regex("^[A-Z0-9-]+$", var.storage_bucket_location))
    error_message = "Bucket location must be a valid Cloud Storage location (e.g., US-CENTRAL1, EUROPE-WEST1)."
  }
}

variable "storage_bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# ============================================================================
# Cloud Dataflow Configuration
# ============================================================================

variable "dataflow_job_name" {
  description = "Name of the Dataflow streaming job"
  type        = string
  default     = "supply-chain-streaming"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){0,38}[a-z0-9]$", var.dataflow_job_name))
    error_message = "Job name must be 1-40 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "dataflow_machine_type" {
  description = "Machine type for Dataflow workers"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition     = can(regex("^[a-z0-9]+-[a-z0-9]+-[0-9]+$", var.dataflow_machine_type))
    error_message = "Machine type must be a valid GCP machine type (e.g., n1-standard-2, e2-medium)."
  }
}

variable "dataflow_max_workers" {
  description = "Maximum number of Dataflow workers"
  type        = number
  default     = 5
  validation {
    condition     = var.dataflow_max_workers >= 1 && var.dataflow_max_workers <= 100
    error_message = "Maximum workers must be between 1 and 100."
  }
}

variable "dataflow_num_workers" {
  description = "Initial number of Dataflow workers"
  type        = number
  default     = 2
  validation {
    condition     = var.dataflow_num_workers >= 1 && var.dataflow_num_workers <= var.dataflow_max_workers
    error_message = "Number of workers must be between 1 and max_workers."
  }
}

variable "dataflow_disk_size_gb" {
  description = "Disk size in GB for Dataflow workers"
  type        = number
  default     = 30
  validation {
    condition     = var.dataflow_disk_size_gb >= 10 && var.dataflow_disk_size_gb <= 1000
    error_message = "Disk size must be between 10 and 1000 GB."
  }
}

variable "dataflow_network" {
  description = "VPC network for Dataflow workers"
  type        = string
  default     = "default"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){0,61}[a-z0-9]$", var.dataflow_network))
    error_message = "Network name must be 1-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "dataflow_subnetwork" {
  description = "Subnetwork for Dataflow workers (full resource name or just the name)"
  type        = string
  default     = null
}

variable "dataflow_service_account_email" {
  description = "Service account email for Dataflow workers (if not provided, will create one)"
  type        = string
  default     = null
}

# ============================================================================
# Service Account Configuration
# ============================================================================

variable "create_service_accounts" {
  description = "Whether to create service accounts for the services"
  type        = bool
  default     = true
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Supply Chain Visibility Service Account"
}

# ============================================================================
# IAM and Security Configuration
# ============================================================================

variable "enable_uniform_bucket_level_access" {
  description = "Whether to enable uniform bucket-level access on Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_spanner_deletion_protection" {
  description = "Whether to enable deletion protection on Spanner instance"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# ============================================================================
# Monitoring and Logging Configuration
# ============================================================================

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Whether to enable Cloud Logging for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# ============================================================================
# Resource Tagging
# ============================================================================

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "supply-chain-visibility"
    environment = "dev"
    terraform   = "true"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys and values must be 1-63 characters and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# ============================================================================
# Cost Optimization Configuration
# ============================================================================

variable "enable_cost_optimization" {
  description = "Whether to enable cost optimization features"
  type        = bool
  default     = true
}

variable "preemptible_dataflow_workers" {
  description = "Whether to use preemptible instances for Dataflow workers"
  type        = bool
  default     = false
}

variable "auto_delete_buckets" {
  description = "Whether to automatically delete storage buckets on destroy"
  type        = bool
  default     = false
}