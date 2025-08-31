# Project and Location Variables
variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must be at least 6 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Networking Variables
variable "vpc_name" {
  description = "Name of the VPC network for HPC cluster"
  type        = string
  default     = "hpc-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet for HPC compute instances"
  type        = string
  default     = "hpc-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the HPC subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Storage Variables
variable "hpc_bucket_name" {
  description = "Name of the Cloud Storage bucket for HPC data (will be made globally unique with random suffix)"
  type        = string
  default     = "hpc-data"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.hpc_bucket_name)) && length(var.hpc_bucket_name) <= 55
    error_message = "Bucket name must contain only lowercase letters, numbers, hyphens, and underscores, and be 55 characters or less."
  }
}

variable "storage_class" {
  description = "Default storage class for the HPC data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Compute Variables
variable "hpc_machine_type" {
  description = "Machine type for HPC compute instances"
  type        = string
  default     = "c2-standard-16"
  validation {
    condition = contains([
      "c2-standard-4", "c2-standard-8", "c2-standard-16", "c2-standard-30", "c2-standard-60",
      "c2d-standard-4", "c2d-standard-8", "c2d-standard-16", "c2d-standard-32", "c2d-standard-56", "c2d-standard-112",
      "c3-standard-4", "c3-standard-8", "c3-standard-22", "c3-standard-44", "c3-standard-88", "c3-standard-176"
    ], var.hpc_machine_type)
    error_message = "Machine type must be a valid compute-optimized instance type."
  }
}

variable "hpc_instance_count" {
  description = "Number of HPC compute instances to create"
  type        = number
  default     = 2
  validation {
    condition     = var.hpc_instance_count >= 1 && var.hpc_instance_count <= 100
    error_message = "HPC instance count must be between 1 and 100."
  }
}

variable "gpu_machine_type" {
  description = "Machine type for GPU compute instances"
  type        = string
  default     = "n1-standard-8"
  validation {
    condition = contains([
      "n1-standard-4", "n1-standard-8", "n1-standard-16", "n1-standard-32", "n1-standard-64", "n1-standard-96",
      "a2-highgpu-1g", "a2-highgpu-2g", "a2-highgpu-4g", "a2-highgpu-8g",
      "g2-standard-4", "g2-standard-8", "g2-standard-12", "g2-standard-16", "g2-standard-24", "g2-standard-32"
    ], var.gpu_machine_type)
    error_message = "GPU machine type must be a valid GPU-compatible instance type."
  }
}

variable "gpu_instance_count" {
  description = "Number of GPU compute instances to create"
  type        = number
  default     = 1
  validation {
    condition     = var.gpu_instance_count >= 0 && var.gpu_instance_count <= 10
    error_message = "GPU instance count must be between 0 and 10."
  }
}

variable "gpu_type" {
  description = "Type of GPU accelerator to attach"
  type        = string
  default     = "nvidia-tesla-t4"
  validation {
    condition = contains([
      "nvidia-tesla-k80", "nvidia-tesla-p4", "nvidia-tesla-p100", "nvidia-tesla-v100",
      "nvidia-tesla-t4", "nvidia-tesla-a100", "nvidia-l4", "nvidia-h100-80gb"
    ], var.gpu_type)
    error_message = "GPU type must be a valid NVIDIA GPU accelerator type."
  }
}

variable "gpu_count" {
  description = "Number of GPUs per instance"
  type        = number
  default     = 1
  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 8
    error_message = "GPU count per instance must be between 1 and 8."
  }
}

# Disk Variables
variable "hpc_disk_size" {
  description = "Boot disk size for HPC compute instances (in GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.hpc_disk_size >= 20 && var.hpc_disk_size <= 65536
    error_message = "HPC disk size must be between 20GB and 65536GB."
  }
}

variable "gpu_disk_size" {
  description = "Boot disk size for GPU compute instances (in GB)"
  type        = number
  default     = 200
  validation {
    condition     = var.gpu_disk_size >= 20 && var.gpu_disk_size <= 65536
    error_message = "GPU disk size must be between 20GB and 65536GB."
  }
}

variable "disk_type" {
  description = "Type of persistent disk for compute instances"
  type        = string
  default     = "pd-ssd"
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced", "pd-extreme"
    ], var.disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced, pd-extreme."
  }
}

# Batch Job Variables
variable "enable_batch_jobs" {
  description = "Whether to create sample batch jobs for testing"
  type        = bool
  default     = true
}

variable "batch_machine_type" {
  description = "Machine type for Cloud Batch jobs"
  type        = string
  default     = "c2-standard-8"
}

variable "batch_task_count" {
  description = "Number of tasks for sample batch jobs"
  type        = number
  default     = 4
  validation {
    condition     = var.batch_task_count >= 1 && var.batch_task_count <= 1000
    error_message = "Batch task count must be between 1 and 1000."
  }
}

variable "batch_parallelism" {
  description = "Number of tasks to run in parallel for batch jobs"
  type        = number
  default     = 2
  validation {
    condition     = var.batch_parallelism >= 1 && var.batch_parallelism <= 100
    error_message = "Batch parallelism must be between 1 and 100."
  }
}

# Reservation Variables
variable "enable_gpu_reservation" {
  description = "Whether to create GPU reservations for predictable access"
  type        = bool
  default     = false
}

variable "reservation_start_time" {
  description = "Start time for GPU reservation (future time in RFC3339 format)"
  type        = string
  default     = ""
  validation {
    condition = var.reservation_start_time == "" || can(formatdate("2006-01-02T15:04:05Z", var.reservation_start_time))
    error_message = "Reservation start time must be empty or in RFC3339 format (YYYY-MM-DDTHH:MM:SSZ)."
  }
}

variable "reservation_duration" {
  description = "Duration of GPU reservation in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.reservation_duration >= 3600 && var.reservation_duration <= 86400
    error_message = "Reservation duration must be between 1 hour (3600s) and 24 hours (86400s)."
  }
}

# Monitoring Variables
variable "enable_monitoring" {
  description = "Whether to create monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Budget amount in USD for cost alerting"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 10000
    error_message = "Budget amount must be between 1 and 10000 USD."
  }
}

# Tagging Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "hpc"
    project     = "scientific-computing"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# OS Image Variables
variable "hpc_image_family" {
  description = "Image family for HPC compute instances"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "hpc_image_project" {
  description = "Project containing the image family for HPC instances"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "gpu_image_family" {
  description = "Image family for GPU compute instances"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "gpu_image_project" {
  description = "Project containing the image family for GPU instances"
  type        = string
  default     = "ubuntu-os-cloud"
}