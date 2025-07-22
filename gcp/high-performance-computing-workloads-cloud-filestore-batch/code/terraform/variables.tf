# Input variables for the HPC workloads with Cloud Filestore and Batch infrastructure

variable "project_id" {
  description = "The ID of the Google Cloud Project where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone where zonal resources will be created"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "hpc-demo"
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 20
    error_message = "Environment name must be between 1 and 20 characters."
  }
}

variable "network_name" {
  description = "Name for the VPC network"
  type        = string
  default     = "hpc-network"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.network_name))
    error_message = "Network name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "subnet_name" {
  description = "Name for the VPC subnet"
  type        = string
  default     = "hpc-subnet"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.subnet_name))
    error_message = "Subnet name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "subnet_cidr" {
  description = "CIDR range for the VPC subnet"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "filestore_name" {
  description = "Name for the Cloud Filestore instance"
  type        = string
  default     = "hpc-storage"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.filestore_name))
    error_message = "Filestore name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "filestore_tier" {
  description = "Service tier for Cloud Filestore instance"
  type        = string
  default     = "ENTERPRISE"
  validation {
    condition = contains([
      "BASIC_HDD", "BASIC_SSD", "HIGH_SCALE_SSD", "ZONAL", "REGIONAL", "ENTERPRISE"
    ], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD, ZONAL, REGIONAL, ENTERPRISE."
  }
}

variable "filestore_capacity_gb" {
  description = "Storage capacity for Cloud Filestore instance in GB"
  type        = number
  default     = 2560
  validation {
    condition     = var.filestore_capacity_gb >= 1024 && var.filestore_capacity_gb <= 102400
    error_message = "Filestore capacity must be between 1024 GB and 102400 GB."
  }
}

variable "filestore_file_share_name" {
  description = "Name of the file share on the Filestore instance"
  type        = string
  default     = "hpc_data"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.filestore_file_share_name))
    error_message = "File share name must contain only letters, numbers, and underscores."
  }
}

variable "instance_template_name" {
  description = "Name for the compute instance template"
  type        = string
  default     = "hpc-node-template"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.instance_template_name))
    error_message = "Instance template name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "instance_machine_type" {
  description = "Machine type for HPC compute instances"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "c2-standard-4", "c2-standard-8", "c2-standard-16", "c2-standard-30",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.instance_machine_type)
    error_message = "Machine type must be a valid GCP compute machine type."
  }
}

variable "instance_group_name" {
  description = "Name for the managed instance group"
  type        = string
  default     = "hpc-compute-group"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.instance_group_name))
    error_message = "Instance group name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "autoscaler_min_replicas" {
  description = "Minimum number of instances in the autoscaler"
  type        = number
  default     = 0
  validation {
    condition     = var.autoscaler_min_replicas >= 0 && var.autoscaler_min_replicas <= 10
    error_message = "Minimum replicas must be between 0 and 10."
  }
}

variable "autoscaler_max_replicas" {
  description = "Maximum number of instances in the autoscaler"
  type        = number
  default     = 10
  validation {
    condition     = var.autoscaler_max_replicas >= 1 && var.autoscaler_max_replicas <= 100
    error_message = "Maximum replicas must be between 1 and 100."
  }
}

variable "autoscaler_cpu_target" {
  description = "Target CPU utilization for autoscaling (0.0 to 1.0)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.autoscaler_cpu_target >= 0.1 && var.autoscaler_cpu_target <= 1.0
    error_message = "CPU target must be between 0.1 and 1.0."
  }
}

variable "monitoring_notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition = var.monitoring_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_notification_email))
    error_message = "If provided, must be a valid email address."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Whether to enable enhanced logging for HPC workloads"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default = {
    "use-case"    = "high-performance-computing"
    "managed-by"  = "terraform"
    "recipe"      = "hpc-filestore-batch"
  }
  validation {
    condition     = length(var.tags) <= 10
    error_message = "Cannot specify more than 10 tags."
  }
}