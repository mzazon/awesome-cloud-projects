# Variables for Carbon-Efficient Batch Processing Infrastructure
# Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment (us-central1 recommended for high CFE%)"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for compute resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

# Resource Naming
variable "name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "carbon-batch"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "Name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 1-20 characters long."
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

# Carbon Intelligence Configuration
variable "carbon_intensity_threshold" {
  description = "Carbon intensity threshold (gCO2e/kWh) for scheduling decisions"
  type        = number
  default     = 200
  validation {
    condition     = var.carbon_intensity_threshold >= 50 && var.carbon_intensity_threshold <= 1000
    error_message = "Carbon intensity threshold must be between 50 and 1000 gCO2e/kWh."
  }
}

variable "cfe_percentage_threshold" {
  description = "Minimum Carbon-Free Energy percentage for immediate job execution"
  type        = number
  default     = 70
  validation {
    condition     = var.cfe_percentage_threshold >= 0 && var.cfe_percentage_threshold <= 100
    error_message = "CFE percentage threshold must be between 0 and 100."
  }
}

# Batch Job Configuration
variable "batch_job_parallelism" {
  description = "Number of parallel tasks in batch job"
  type        = number
  default     = 3
  validation {
    condition     = var.batch_job_parallelism >= 1 && var.batch_job_parallelism <= 10
    error_message = "Batch job parallelism must be between 1 and 10."
  }
}

variable "batch_machine_type" {
  description = "Machine type for batch job compute resources"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = can(regex("^[a-z][0-9]+-[a-z]+-[0-9]+$", var.batch_machine_type))
    error_message = "Machine type must be a valid GCP machine type (e.g., e2-standard-2)."
  }
}

variable "use_preemptible_instances" {
  description = "Use preemptible instances for batch jobs to reduce cost and carbon impact"
  type        = bool
  default     = true
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for carbon data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Age in days for transitioning objects to lower-cost storage classes"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age >= 1 && var.bucket_lifecycle_age <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

# Monitoring Configuration
variable "enable_carbon_monitoring" {
  description = "Enable custom carbon footprint monitoring and alerting"
  type        = bool
  default     = true
}

variable "monitoring_retention_days" {
  description = "Retention period for monitoring data in days"
  type        = number
  default     = 90
  validation {
    condition     = var.monitoring_retention_days >= 30 && var.monitoring_retention_days <= 365
    error_message = "Monitoring retention days must be between 30 and 365."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for carbon scheduler function (MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for carbon scheduler function (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 10 && var.function_timeout <= 540
    error_message = "Function timeout must be between 10 and 540 seconds."
  }
}

# Security Configuration
variable "enable_audit_logging" {
  description = "Enable audit logging for all resources"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to invoke Cloud Functions"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "carbon-efficient-batch"
    managed-by  = "terraform"
    environment = "development"
    purpose     = "sustainability-intelligence"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}