# Variables for Visual Document Processing with Cloud Filestore and Vision AI Solution
# This file defines all configurable parameters for the infrastructure deployment

# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources (must be within the specified region)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

# ============================================================================
# RESOURCE NAMING CONFIGURATION
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "visual-doc-proc"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix to append to resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# ============================================================================
# FILESTORE CONFIGURATION
# ============================================================================

variable "filestore_tier" {
  description = "Filestore service tier (BASIC_HDD, BASIC_SSD, STANDARD, PREMIUM, ENTERPRISE)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["BASIC_HDD", "BASIC_SSD", "STANDARD", "PREMIUM", "ENTERPRISE"], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, STANDARD, PREMIUM, ENTERPRISE."
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB (minimum varies by tier)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.filestore_capacity_gb >= 1024 && var.filestore_capacity_gb <= 65536
    error_message = "Filestore capacity must be between 1024 GB and 65536 GB."
  }
}

variable "filestore_file_share_name" {
  description = "Name of the file share within the Filestore instance"
  type        = string
  default     = "documents"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.filestore_file_share_name))
    error_message = "File share name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "filestore_network" {
  description = "VPC network for Filestore connectivity"
  type        = string
  default     = "default"
}

# ============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ============================================================================

variable "functions_runtime" {
  description = "Runtime for Cloud Functions (nodejs18, nodejs20, python39, python310, python311)"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311", "go119", "go120", "go121"
    ], var.functions_runtime)
    error_message = "Functions runtime must be a supported Cloud Functions runtime."
  }
}

variable "monitor_function_memory" {
  description = "Memory allocation for the file monitor function (MB)"
  type        = string
  default     = "256M"
  
  validation {
    condition     = contains(["128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"], var.monitor_function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
  }
}

variable "processor_function_memory" {
  description = "Memory allocation for the Vision AI processor function (MB)"
  type        = string
  default     = "1024M"
  
  validation {
    condition     = contains(["128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"], var.processor_function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

# ============================================================================
# PUB/SUB CONFIGURATION
# ============================================================================

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (e.g., '604800s' for 7 days)"
  type        = string
  default     = "604800s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '604800s')."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

variable "storage_location" {
  description = "Location for Cloud Storage buckets (US, EU, ASIA, or specific region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "europe-west1", "asia-east1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_storage_lifecycle" {
  description = "Enable lifecycle management on Cloud Storage buckets"
  type        = bool
  default     = true
}

# ============================================================================
# COMPUTE ENGINE CONFIGURATION
# ============================================================================

variable "client_machine_type" {
  description = "Machine type for the Filestore client Compute Engine instance"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.client_machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type."
  }
}

variable "client_boot_disk_size_gb" {
  description = "Boot disk size for the client instance in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.client_boot_disk_size_gb >= 10 && var.client_boot_disk_size_gb <= 100
    error_message = "Boot disk size must be between 10 and 100 GB."
  }
}

variable "client_image_family" {
  description = "OS image family for the client instance"
  type        = string
  default     = "ubuntu-2004-lts"
  
  validation {
    condition = contains([
      "ubuntu-2004-lts", "ubuntu-2204-lts", "debian-11", "debian-12", "centos-7", "rhel-8"
    ], var.client_image_family)
    error_message = "Image family must be a supported OS image family."
  }
}

variable "client_image_project" {
  description = "Project containing the OS image for the client instance"
  type        = string
  default     = "ubuntu-os-cloud"
}

# ============================================================================
# SECURITY AND IAM CONFIGURATION
# ============================================================================

variable "enable_private_google_access" {
  description = "Enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

variable "enable_api_audit_logs" {
  description = "Enable audit logs for Google Cloud APIs"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "Additional IAM roles to grant to the service account"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for role in var.service_account_roles : can(regex("^roles/", role))])
    error_message = "All roles must start with 'roles/'."
  }
}

# ============================================================================
# MONITORING AND LOGGING CONFIGURATION
# ============================================================================

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for all resources"
  type        = bool
  default     = true
}

variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days (10 years)."
  }
}

# ============================================================================
# COST OPTIMIZATION CONFIGURATION
# ============================================================================

variable "enable_preemptible_instances" {
  description = "Use preemptible instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

variable "auto_delete_resources" {
  description = "Automatically delete resources when Terraform destroy is run"
  type        = bool
  default     = true
}

# ============================================================================
# FEATURE FLAGS
# ============================================================================

variable "create_client_instance" {
  description = "Create a Compute Engine client instance for demonstration"
  type        = bool
  default     = true
}

variable "create_sample_functions" {
  description = "Create sample Cloud Functions with demo code"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# ============================================================================
# ADVANCED CONFIGURATION
# ============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}