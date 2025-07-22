# =====================================
# Variables for Adaptive Marketing Campaign Intelligence
# with Vertex AI Agents and Google Workspace Flows
# =====================================

# =====================================
# Project and Region Configuration
# =====================================

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid Google Cloud project identifier."
  }
}

variable "region" {
  description = "Google Cloud region for compute resources (Vertex AI, Cloud Storage)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1", "northamerica-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Vertex AI support."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "cost_center" {
  description = "Cost center or billing code for resource allocation and tracking"
  type        = string
  default     = "marketing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cost_center))
    error_message = "Cost center must contain only lowercase letters, numbers, and hyphens."
  }
}

# =====================================
# BigQuery Configuration
# =====================================

variable "dataset_name" {
  description = "Base name for the BigQuery dataset (suffix will be auto-generated)"
  type        = string
  default     = "marketing_data"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must support BigQuery ML)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-northeast2", "asia-southeast1", "asia-south1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid multi-region or region that supports BigQuery ML."
  }
}

variable "table_expiration_days" {
  description = "Number of days before BigQuery tables expire (0 = never expire)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.table_expiration_days >= 0 && var.table_expiration_days <= 3650
    error_message = "Table expiration must be between 0 and 3650 days (10 years)."
  }
}

# =====================================
# Storage Configuration
# =====================================

variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "kms_key_name" {
  description = "KMS key name for bucket encryption (optional, uses Google-managed keys if not specified)"
  type        = string
  default     = null
  
  validation {
    condition = var.kms_key_name == null || can(regex("^projects/.+/locations/.+/keyRings/.+/cryptoKeys/.+$", var.kms_key_name))
    error_message = "KMS key name must be in the format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}"
  }
}

# =====================================
# Vertex AI Workbench Configuration
# =====================================

variable "workbench_machine_type" {
  description = "Machine type for Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
  
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8", "n1-highmem-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16",
      "n2-highmem-2", "n2-highmem-4", "n2-highmem-8", "n2-highmem-16"
    ], var.workbench_machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type supported by Vertex AI Workbench."
  }
}

variable "workbench_disk_size_gb" {
  description = "Size of additional data disk for Workbench instance in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.workbench_disk_size_gb >= 10 && var.workbench_disk_size_gb <= 10000
    error_message = "Workbench disk size must be between 10 GB and 10,000 GB."
  }
}

variable "disable_workbench_public_ip" {
  description = "Whether to disable public IP for Workbench instance (recommended for production)"
  type        = bool
  default     = true
}

variable "workbench_owners" {
  description = "List of email addresses for Workbench instance owners"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for owner in var.workbench_owners : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", owner))
    ])
    error_message = "All workbench owners must be valid email addresses."
  }
}

# =====================================
# Access Control and Security
# =====================================

variable "data_analysts_group" {
  description = "Google Group email for data analysts (optional, grants read access to BigQuery dataset)"
  type        = string
  default     = ""
  
  validation {
    condition = var.data_analysts_group == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.data_analysts_group))
    error_message = "Data analysts group must be a valid email address or empty string."
  }
}

variable "marketing_team_emails" {
  description = "List of email addresses for marketing team members (for workflow notifications)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.marketing_team_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All marketing team emails must be valid email addresses."
  }
}

# =====================================
# Monitoring and Alerting
# =====================================

variable "enable_monitoring" {
  description = "Whether to enable monitoring and alerting for the solution"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for system alerts and notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

# =====================================
# Vertex AI Configuration
# =====================================

variable "vertex_ai_training_region" {
  description = "Region for Vertex AI training jobs (can be different from main region for optimization)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vertex_ai_training_region == "" || contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_training_region)
    error_message = "Vertex AI training region must be a valid region with Vertex AI support or empty string."
  }
}

variable "enable_vertex_ai_agents" {
  description = "Whether to enable Vertex AI Agents (currently in preview, requires allowlist access)"
  type        = bool
  default     = false
}

# =====================================
# Workspace Integration Configuration
# =====================================

variable "workspace_domain" {
  description = "Google Workspace domain name for API integration"
  type        = string
  default     = ""
  
  validation {
    condition = var.workspace_domain == "" || can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.workspace_domain))
    error_message = "Workspace domain must be a valid domain name or empty string."
  }
}

variable "enable_workspace_flows" {
  description = "Whether to enable Google Workspace Flows integration (requires appropriate licensing)"
  type        = bool
  default     = false
}

variable "gmail_api_enabled" {
  description = "Whether to enable Gmail API for automated email campaigns"
  type        = bool
  default     = true
}

variable "sheets_api_enabled" {
  description = "Whether to enable Google Sheets API for dashboard integration"
  type        = bool
  default     = true
}

variable "docs_api_enabled" {
  description = "Whether to enable Google Docs API for automated report generation"
  type        = bool
  default     = true
}

variable "calendar_api_enabled" {
  description = "Whether to enable Google Calendar API for meeting scheduling"
  type        = bool
  default     = true
}

# =====================================
# Data Processing Configuration
# =====================================

variable "enable_data_streaming" {
  description = "Whether to enable real-time data streaming capabilities"
  type        = bool
  default     = false
}

variable "streaming_buffer_size" {
  description = "Buffer size for streaming data ingestion (in MB)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.streaming_buffer_size >= 1 && var.streaming_buffer_size <= 1000
    error_message = "Streaming buffer size must be between 1 MB and 1000 MB."
  }
}

variable "enable_real_time_analytics" {
  description = "Whether to enable real-time analytics capabilities with Pub/Sub"
  type        = bool
  default     = false
}

# =====================================
# Cost Optimization Configuration
# =====================================

variable "enable_cost_optimization" {
  description = "Whether to enable cost optimization features (lifecycle policies, etc.)"
  type        = bool
  default     = true
}

variable "bigquery_slot_commitment" {
  description = "BigQuery slot commitment for predictable costs (0 = on-demand pricing)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.bigquery_slot_commitment >= 0 && var.bigquery_slot_commitment <= 10000
    error_message = "BigQuery slot commitment must be between 0 and 10,000 slots."
  }
}

variable "storage_archive_after_days" {
  description = "Number of days after which to archive storage objects (0 = disable archiving)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.storage_archive_after_days >= 0 && var.storage_archive_after_days <= 3650
    error_message = "Storage archive period must be between 0 and 3650 days."
  }
}

# =====================================
# Advanced Configuration
# =====================================

variable "enable_audit_logging" {
  description = "Whether to enable detailed audit logging for compliance"
  type        = bool
  default     = true
}

variable "enable_data_loss_prevention" {
  description = "Whether to enable Data Loss Prevention (DLP) scanning"
  type        = bool
  default     = false
}

variable "custom_labels" {
  description = "Additional custom labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.custom_labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Custom labels must have lowercase keys starting with a letter, and lowercase values. Both can contain letters, numbers, underscores, and hyphens."
  }
}

variable "network_project_id" {
  description = "Project ID for shared VPC network (if different from main project)"
  type        = string
  default     = ""
  
  validation {
    condition = var.network_project_id == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.network_project_id))
    error_message = "Network project ID must be a valid Google Cloud project identifier or empty string."
  }
}

variable "vpc_network_name" {
  description = "Name of VPC network to use (if not specified, uses default network)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vpc_network_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.vpc_network_name))
    error_message = "VPC network name must be a valid network name or empty string."
  }
}

variable "subnet_name" {
  description = "Name of subnet to use for compute resources"
  type        = string
  default     = ""
  
  validation {
    condition = var.subnet_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.subnet_name))
    error_message = "Subnet name must be a valid subnet name or empty string."
  }
}