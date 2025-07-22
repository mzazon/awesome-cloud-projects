# Variables for high-performance data science workflows with NetApp Volumes and Vertex AI Workbench

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (NetApp storage pools)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region where NetApp Volumes is available."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (Vertex AI Workbench instances)"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0 && can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment label for resource organization (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network to create for high-performance data science workflows"
  type        = string
  default     = "netapp-ml-network"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.network_name))
    error_message = "Network name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet (must provide adequate IP space for scaling)"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# NetApp Volumes Configuration
variable "storage_pool_name" {
  description = "Name for the NetApp storage pool (will have random suffix appended)"
  type        = string
  default     = "ml-pool"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.storage_pool_name))
    error_message = "Storage pool name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "storage_pool_capacity_gib" {
  description = "Storage pool capacity in GiB (minimum 1024 GiB for Premium service level)"
  type        = number
  default     = 1024
  validation {
    condition     = var.storage_pool_capacity_gib >= 1024 && var.storage_pool_capacity_gib <= 102400
    error_message = "Storage pool capacity must be between 1024 GiB and 102400 GiB."
  }
}

variable "storage_service_level" {
  description = "NetApp service level for performance optimization (PREMIUM, EXTREME, or FLEX)"
  type        = string
  default     = "PREMIUM"
  validation {
    condition     = contains(["PREMIUM", "EXTREME", "FLEX"], var.storage_service_level)
    error_message = "Service level must be one of: PREMIUM, EXTREME, FLEX."
  }
}

variable "volume_name" {
  description = "Name for the NetApp volume for ML datasets (will have random suffix appended)"
  type        = string
  default     = "ml-datasets"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.volume_name))
    error_message = "Volume name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "volume_capacity_gib" {
  description = "Volume capacity in GiB for ML datasets and models"
  type        = number
  default     = 500
  validation {
    condition     = var.volume_capacity_gib >= 100 && var.volume_capacity_gib <= 102400
    error_message = "Volume capacity must be between 100 GiB and 102400 GiB."
  }
}

variable "volume_share_name" {
  description = "NFS share name for the volume"
  type        = string
  default     = "ml-datasets"
  validation {
    condition     = can(regex("^[a-zA-Z][-a-zA-Z0-9_]*[a-zA-Z0-9]$", var.volume_share_name))
    error_message = "Share name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "volume_protocols" {
  description = "File system protocols supported by the volume"
  type        = list(string)
  default     = ["NFSV3"]
  validation {
    condition = length(var.volume_protocols) > 0 && alltrue([
      for protocol in var.volume_protocols : contains(["NFSV3", "NFSV4"], protocol)
    ])
    error_message = "Volume protocols must be a non-empty list containing only NFSV3 and/or NFSV4."
  }
}

# Vertex AI Workbench Configuration
variable "workbench_name" {
  description = "Name for the Vertex AI Workbench instance (will have random suffix appended)"
  type        = string
  default     = "ml-workbench"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.workbench_name))
    error_message = "Workbench name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "workbench_machine_type" {
  description = "Machine type for the Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8", "n1-highmem-16",
      "a2-highgpu-1g", "a2-highgpu-2g", "a2-highgpu-4g", "a2-highgpu-8g"
    ], var.workbench_machine_type)
    error_message = "Machine type must be a valid Google Compute Engine machine type."
  }
}

variable "enable_gpu" {
  description = "Whether to enable GPU acceleration for machine learning workloads"
  type        = bool
  default     = true
}

variable "gpu_type" {
  description = "GPU type for machine learning acceleration"
  type        = string
  default     = "NVIDIA_TESLA_T4"
  validation {
    condition = contains([
      "NVIDIA_TESLA_K80", "NVIDIA_TESLA_P4", "NVIDIA_TESLA_P100",
      "NVIDIA_TESLA_V100", "NVIDIA_TESLA_T4", "NVIDIA_TESLA_A100"
    ], var.gpu_type)
    error_message = "GPU type must be a valid NVIDIA GPU type available in Google Cloud."
  }
}

variable "gpu_count" {
  description = "Number of GPUs to attach to the workbench instance"
  type        = number
  default     = 1
  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB for the Workbench instance"
  type        = number
  default     = 100
  validation {
    condition     = var.boot_disk_size_gb >= 50 && var.boot_disk_size_gb <= 1000
    error_message = "Boot disk size must be between 50 GB and 1000 GB."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type for optimal performance"
  type        = string
  default     = "PD_SSD"
  validation {
    condition     = contains(["PD_STANDARD", "PD_SSD", "PD_BALANCED"], var.boot_disk_type)
    error_message = "Boot disk type must be one of: PD_STANDARD, PD_SSD, PD_BALANCED."
  }
}

variable "workbench_image_family" {
  description = "Image family for the Vertex AI Workbench instance"
  type        = string
  default     = "tf-ent-2-11-cu113-notebooks"
  validation {
    condition = contains([
      "tf-ent-2-11-cu113-notebooks", "tf-ent-2-12-cu118-notebooks",
      "pytorch-2-0-cpu-notebooks", "pytorch-2-0-gpu-notebooks",
      "common-cpu-notebooks", "common-gpu-notebooks"
    ], var.workbench_image_family)
    error_message = "Image family must be a valid Deep Learning VM image family."
  }
}

variable "workbench_image_project" {
  description = "Project containing the Workbench image"
  type        = string
  default     = "deeplearning-platform-release"
}

# Cloud Storage Configuration
variable "bucket_name" {
  description = "Name for the Cloud Storage bucket for data lake integration (will have random suffix appended)"
  type        = string
  default     = "ml-datalake"
  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9_.]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must start and end with a letter or number, and contain only lowercase letters, numbers, hyphens, underscores, and periods."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (should match region for optimal performance)"
  type        = string
  default     = "US-CENTRAL1"
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Security Configuration
variable "enable_shielded_vm" {
  description = "Enable Shielded VM features for enhanced security"
  type        = bool
  default     = true
}

variable "enable_secure_boot" {
  description = "Enable Secure Boot for the Workbench instance"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable Virtual Trusted Platform Module (vTPM)"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable integrity monitoring for the Workbench instance"
  type        = bool
  default     = true
}

# Performance Configuration
variable "enable_ip_forwarding" {
  description = "Enable IP forwarding for the Workbench instance"
  type        = bool
  default     = false
}

variable "preemptible" {
  description = "Create preemptible Workbench instance for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

# Tags and Labels
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "network_tags" {
  description = "Network tags to apply to the Workbench instance for firewall rules"
  type        = list(string)
  default     = ["ml-workbench", "data-science"]
  validation {
    condition = alltrue([
      for tag in var.network_tags : can(regex("^[a-z0-9-]+$", tag))
    ])
    error_message = "Network tags must contain only lowercase letters, numbers, and hyphens."
  }
}