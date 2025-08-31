# Core project configuration variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid GCP region name."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid GCP zone name."
  }
}

# Resource naming and tagging variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "secure-traffic"
  
  validation {
    condition = can(regex("^[a-z0-9-]{1,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 1-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "secure-traffic-processing"
    managed-by  = "terraform"
    recipe      = "service-extensions-confidential"
  }
}

# Confidential VM configuration variables
variable "confidential_vm_machine_type" {
  description = "Machine type for the Confidential VM (must support Confidential Computing)"
  type        = string
  default     = "n2d-standard-4"
  
  validation {
    condition = can(regex("^n2d-", var.confidential_vm_machine_type))
    error_message = "Machine type must be N2D series for AMD SEV-SNP Confidential Computing support."
  }
}

variable "confidential_vm_boot_disk_size" {
  description = "Boot disk size in GB for the Confidential VM"
  type        = number
  default     = 50
  
  validation {
    condition = var.confidential_vm_boot_disk_size >= 20 && var.confidential_vm_boot_disk_size <= 1000
    error_message = "Boot disk size must be between 20 and 1000 GB."
  }
}

variable "confidential_vm_boot_disk_type" {
  description = "Boot disk type for the Confidential VM"
  type        = string
  default     = "pd-ssd"
  
  validation {
    condition = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.confidential_vm_boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "confidential_compute_type" {
  description = "Type of Confidential Computing technology to use"
  type        = string
  default     = "SEV_SNP"
  
  validation {
    condition = contains(["SEV", "SEV_SNP", "TDX"], var.confidential_compute_type)
    error_message = "Confidential compute type must be one of: SEV, SEV_SNP, TDX."
  }
}

# Cloud KMS configuration variables
variable "kms_key_rotation_period" {
  description = "Rotation period for KMS keys in seconds (default: 90 days)"
  type        = string
  default     = "7776000s"  # 90 days
  
  validation {
    condition = can(regex("^[0-9]+s$", var.kms_key_rotation_period))
    error_message = "Key rotation period must be in seconds format (e.g., '7776000s')."
  }
}

variable "kms_protection_level" {
  description = "Protection level for KMS keys"
  type        = string
  default     = "SOFTWARE"
  
  validation {
    condition = contains(["SOFTWARE", "HSM"], var.kms_protection_level)
    error_message = "KMS protection level must be either SOFTWARE or HSM."
  }
}

# Storage configuration variables
variable "storage_class" {
  description = "Storage class for the secure data bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_storage_lifecycle" {
  description = "Enable automatic lifecycle management for storage bucket"
  type        = bool
  default     = true
}

variable "storage_lifecycle_coldline_age" {
  description = "Age in days to transition objects to COLDLINE storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.storage_lifecycle_coldline_age >= 1 && var.storage_lifecycle_coldline_age <= 365
    error_message = "Storage lifecycle coldline age must be between 1 and 365 days."
  }
}

variable "storage_lifecycle_delete_age" {
  description = "Age in days to delete objects from storage"
  type        = number
  default     = 365
  
  validation {
    condition = var.storage_lifecycle_delete_age >= 1 && var.storage_lifecycle_delete_age <= 3650
    error_message = "Storage lifecycle delete age must be between 1 and 3650 days."
  }
}

# Load balancer configuration variables
variable "enable_ssl_certificate" {
  description = "Enable SSL certificate for load balancer"
  type        = bool
  default     = true
}

variable "ssl_certificate_domains" {
  description = "Domains for SSL certificate"
  type        = list(string)
  default     = ["secure-traffic.example.com"]
  
  validation {
    condition = length(var.ssl_certificate_domains) > 0
    error_message = "At least one domain must be specified for SSL certificate."
  }
}

# Network security configuration variables
variable "allowed_source_ranges" {
  description = "CIDR ranges allowed to access the traffic processor"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  
  validation {
    condition = length(var.allowed_source_ranges) > 0
    error_message = "At least one source range must be specified."
  }
}

variable "traffic_processor_port" {
  description = "Port for the traffic processing service"
  type        = number
  default     = 8080
  
  validation {
    condition = var.traffic_processor_port >= 1024 && var.traffic_processor_port <= 65535
    error_message = "Traffic processor port must be between 1024 and 65535."
  }
}

# High availability and monitoring configuration variables
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for resources"
  type        = bool
  default     = true
}

variable "health_check_timeout_seconds" {
  description = "Timeout for health checks in seconds"
  type        = number
  default     = 10
  
  validation {
    condition = var.health_check_timeout_seconds >= 1 && var.health_check_timeout_seconds <= 300
    error_message = "Health check timeout must be between 1 and 300 seconds."
  }
}

variable "health_check_check_interval_seconds" {
  description = "Interval between health checks in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.health_check_check_interval_seconds >= 1 && var.health_check_check_interval_seconds <= 300
    error_message = "Health check interval must be between 1 and 300 seconds."
  }
}

# Service Extensions configuration variables
variable "enable_service_extensions" {
  description = "Enable Service Extensions callout configuration (requires additional setup)"
  type        = bool
  default     = false
}