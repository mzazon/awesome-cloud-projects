# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "ml-training"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Redis Configuration
variable "redis_memory_size_gb" {
  description = "Memory size in GB for Redis instance"
  type        = number
  default     = 5
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_version" {
  description = "Redis version to use"
  type        = string
  default     = "REDIS_7_0"
}

variable "redis_tier" {
  description = "Redis service tier (BASIC or STANDARD_HA)"
  type        = string
  default     = "STANDARD_HA"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either BASIC or STANDARD_HA."
  }
}

variable "redis_auth_enabled" {
  description = "Enable Redis AUTH for security"
  type        = bool
  default     = true
}

# Vertex AI Workbench Configuration
variable "workbench_machine_type" {
  description = "Machine type for Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
}

variable "workbench_accelerator_type" {
  description = "Accelerator type for Vertex AI Workbench"
  type        = string
  default     = "NVIDIA_TESLA_T4"
}

variable "workbench_accelerator_count" {
  description = "Number of accelerators for Vertex AI Workbench"
  type        = number
  default     = 1
}

variable "workbench_boot_disk_size_gb" {
  description = "Boot disk size in GB for Vertex AI Workbench"
  type        = number
  default     = 100
}

variable "workbench_data_disk_size_gb" {
  description = "Data disk size in GB for Vertex AI Workbench"
  type        = number
  default     = 200
}

variable "workbench_disk_type" {
  description = "Disk type for Vertex AI Workbench (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-ssd"
}

# Cloud Storage Configuration
variable "bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
}

variable "bucket_lifecycle_age" {
  description = "Age in days for lifecycle management"
  type        = number
  default     = 90
}

# Cloud Batch Configuration
variable "batch_machine_type" {
  description = "Machine type for Cloud Batch jobs"
  type        = string
  default     = "e2-standard-2"
}

variable "batch_cpu_milli" {
  description = "CPU allocation in milliCPU for batch tasks"
  type        = number
  default     = 2000
}

variable "batch_memory_mib" {
  description = "Memory allocation in MiB for batch tasks"
  type        = number
  default     = 4096
}

variable "batch_task_count" {
  description = "Number of tasks in batch job"
  type        = number
  default     = 1
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "ml-training-network"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "ml-training-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

# Firewall Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboards"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channels for monitoring alerts"
  type        = list(string)
  default     = []
}

# IAM Configuration
variable "service_account_roles" {
  description = "Additional IAM roles for the service account"
  type        = list(string)
  default = [
    "roles/aiplatform.user",
    "roles/storage.objectAdmin",
    "roles/batch.agentReporter",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "training"
    use-case    = "ml-caching"
    team        = "data-science"
  }
}