# Core project configuration variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

# Resource naming and identification
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Data Fusion configuration
variable "data_fusion_edition" {
  description = "Cloud Data Fusion edition (BASIC, ENTERPRISE, DEVELOPER)"
  type        = string
  default     = "DEVELOPER"
  
  validation {
    condition     = contains(["BASIC", "ENTERPRISE", "DEVELOPER"], var.data_fusion_edition)
    error_message = "Data Fusion edition must be one of: BASIC, ENTERPRISE, DEVELOPER."
  }
}

variable "data_fusion_version" {
  description = "Cloud Data Fusion version"
  type        = string
  default     = "6.10.0"
}

variable "enable_stackdriver_logging" {
  description = "Enable Cloud Logging for Data Fusion"
  type        = bool
  default     = true
}

variable "enable_stackdriver_monitoring" {
  description = "Enable Cloud Monitoring for Data Fusion"
  type        = bool
  default     = true
}

variable "enable_rbac" {
  description = "Enable RBAC for Data Fusion"
  type        = bool
  default     = true
}

# Cloud Storage configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage buckets (defaults to region if not specified)"
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to delete old versions of objects"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# BigQuery configuration
variable "bigquery_location" {
  description = "Location for BigQuery dataset (defaults to region if not specified)"
  type        = string
  default     = ""
}

variable "bigquery_delete_contents_on_destroy" {
  description = "If true, delete all tables when destroying the dataset"
  type        = bool
  default     = false
}

variable "bigquery_default_table_expiration_ms" {
  description = "Default expiration time for tables in milliseconds"
  type        = number
  default     = null
}

# Networking configuration
variable "network_name" {
  description = "Name of the VPC network (if empty, default network will be used)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet (if empty, default subnet will be used)"
  type        = string
  default     = ""
}

variable "create_custom_network" {
  description = "Whether to create a custom VPC network for the resources"
  type        = bool
  default     = false
}

variable "network_cidr" {
  description = "CIDR block for the custom VPC network"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

# IAM and security configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for the resources"
  type        = bool
  default     = true
}

variable "data_fusion_authorized_networks" {
  description = "List of authorized networks for Data Fusion private connectivity"
  type        = list(string)
  default     = []
}

# Colab Enterprise configuration
variable "enable_colab_enterprise" {
  description = "Whether to enable Colab Enterprise integration"
  type        = bool
  default     = true
}

# Tagging and labeling
variable "labels" {
  description = "A map of labels to assign to resources"
  type        = map(string)
  default = {
    environment = "dev"
    purpose     = "data-pipeline-prototype"
    managed-by  = "terraform"
  }
}

# Cost management
variable "enable_cost_optimization" {
  description = "Enable cost optimization features like lifecycle policies"
  type        = bool
  default     = true
}

# APIs to enable
variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "datafusion.googleapis.com",
    "notebooks.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}