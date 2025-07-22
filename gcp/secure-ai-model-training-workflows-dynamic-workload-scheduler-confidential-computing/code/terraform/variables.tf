# Project Configuration
variable "project_id" {
  description = "Google Cloud project ID for secure AI training infrastructure"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with GPU support."
  }
}

variable "zone" {
  description = "Google Cloud zone for compute resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "secure-ai-training"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# Compute Configuration
variable "machine_type" {
  description = "Machine type for confidential computing instances"
  type        = string
  default     = "a2-highgpu-1g"
  validation {
    condition = contains([
      "a2-highgpu-1g", "a2-highgpu-2g", "a2-highgpu-4g", "a2-highgpu-8g",
      "a2-megagpu-16g", "a2-ultragpu-1g", "a2-ultragpu-2g", "a2-ultragpu-4g", "a2-ultragpu-8g"
    ], var.machine_type)
    error_message = "Machine type must be a valid A2 GPU-enabled instance type."
  }
}

variable "accelerator_type" {
  description = "GPU accelerator type for AI training"
  type        = string
  default     = "nvidia-tesla-a100"
  validation {
    condition = contains([
      "nvidia-tesla-a100", "nvidia-a100-80gb", "nvidia-tesla-v100",
      "nvidia-tesla-k80", "nvidia-tesla-p4", "nvidia-tesla-p100", "nvidia-tesla-t4"
    ], var.accelerator_type)
    error_message = "Accelerator type must be a valid NVIDIA GPU type."
  }
}

variable "accelerator_count" {
  description = "Number of GPU accelerators per instance"
  type        = number
  default     = 1
  validation {
    condition     = var.accelerator_count >= 1 && var.accelerator_count <= 16
    error_message = "Accelerator count must be between 1 and 16."
  }
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB for confidential VMs"
  type        = number
  default     = 100
  validation {
    condition     = var.boot_disk_size_gb >= 20 && var.boot_disk_size_gb <= 2048
    error_message = "Boot disk size must be between 20GB and 2048GB."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type for confidential VMs"
  type        = string
  default     = "pd-ssd"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Security Configuration
variable "enable_confidential_compute" {
  description = "Enable confidential computing (SEV) for secure training environments"
  type        = bool
  default     = true
}

variable "enable_secure_boot" {
  description = "Enable secure boot for enhanced security"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable virtual TPM for attestation"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable integrity monitoring for security validation"
  type        = bool
  default     = true
}

# Storage Configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.storage_bucket_location)
    error_message = "Storage bucket location must be a valid Cloud Storage location."
  }
}

variable "storage_class" {
  description = "Storage class for training data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for data lineage tracking"
  type        = bool
  default     = true
}

variable "enable_bucket_logging" {
  description = "Enable access logging for compliance"
  type        = bool
  default     = true
}

# KMS Configuration
variable "kms_key_rotation_period" {
  description = "KMS key rotation period in seconds (minimum 86400s = 24h)"
  type        = string
  default     = "2592000s" # 30 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.kms_key_rotation_period))
    error_message = "KMS key rotation period must be in seconds format (e.g., '2592000s')."
  }
}

variable "kms_key_protection_level" {
  description = "Protection level for KMS keys (SOFTWARE or HSM)"
  type        = string
  default     = "HSM"
  validation {
    condition     = contains(["SOFTWARE", "HSM"], var.kms_key_protection_level)
    error_message = "KMS key protection level must be either SOFTWARE or HSM."
  }
}

# Dynamic Workload Scheduler Configuration
variable "enable_dynamic_workload_scheduler" {
  description = "Enable Dynamic Workload Scheduler for cost optimization"
  type        = bool
  default     = true
}

variable "reservation_type" {
  description = "Type of compute reservation (AUTOMATIC or SPECIFIC)"
  type        = string
  default     = "SPECIFIC"
  validation {
    condition     = contains(["AUTOMATIC", "SPECIFIC"], var.reservation_type)
    error_message = "Reservation type must be either AUTOMATIC or SPECIFIC."
  }
}

variable "vm_count" {
  description = "Number of VMs to reserve for training workloads"
  type        = number
  default     = 1
  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 100
    error_message = "VM count must be between 1 and 100."
  }
}

# Vertex AI Configuration
variable "enable_vertex_ai_training" {
  description = "Enable Vertex AI custom training jobs"
  type        = bool
  default     = true
}

variable "vertex_ai_display_name" {
  description = "Display name for Vertex AI training jobs"
  type        = string
  default     = "Secure AI Training Job"
}

variable "container_image_uri" {
  description = "Container image URI for training jobs"
  type        = string
  default     = "gcr.io/deeplearning-platform-release/pytorch-gpu.1-13"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for security and performance metrics"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging for compliance requirements"
  type        = bool
  default     = true
}

variable "monitoring_notification_email" {
  description = "Email address for monitoring alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.monitoring_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_notification_email))
    error_message = "Monitoring notification email must be a valid email address or empty."
  }
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network (will be created if it doesn't exist)"
  type        = string
  default     = "secure-ai-training-network"
}

variable "subnet_name" {
  description = "Name of the subnet for confidential computing"
  type        = string
  default     = "secure-ai-training-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the training subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "enable_private_google_access" {
  description = "Enable private Google access for secure API communication"
  type        = bool
  default     = true
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "secure-ai-training"
    managed-by  = "terraform"
    security    = "confidential-computing"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "network_tags" {
  description = "Network tags for firewall rules and instance identification"
  type        = list(string)
  default     = ["confidential-training", "secure-ai", "gpu-enabled"]
  validation {
    condition = alltrue([
      for tag in var.network_tags : can(regex("^[a-z][a-z0-9-]*$", tag))
    ])
    error_message = "Network tags must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cost Management
variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost management"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD for cost alerts"
  type        = number
  default     = 1000
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.budget_threshold_percent > 0 && var.budget_threshold_percent <= 1.0
    error_message = "Budget threshold percent must be between 0.0 and 1.0."
  }
}