# Project configuration variables
variable "project_id" {
  description = "Google Cloud Project ID for carbon-aware workload orchestration"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6 and 30 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for VM instances"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "carbon-aware"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
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

# BigQuery configuration variables
variable "dataset_location" {
  description = "Location for BigQuery datasets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1",
      "australia-southeast1", "europe-north1", "europe-west1", "europe-west2",
      "europe-west3", "europe-west4", "europe-west6", "us-central1", "us-east1",
      "us-east4", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "carbon_footprint_retention_days" {
  description = "Number of days to retain carbon footprint data in BigQuery"
  type        = number
  default     = 365
  validation {
    condition     = var.carbon_footprint_retention_days >= 30 && var.carbon_footprint_retention_days <= 3650
    error_message = "Retention days must be between 30 and 3650 days."
  }
}

# Cloud Function configuration variables
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go120", "go121",
      "java11", "java17", "dotnet6", "ruby30", "ruby32"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

# Compute Engine configuration variables
variable "machine_type" {
  description = "Machine type for carbon-optimized compute instances"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = can(regex("^(e2|n2|n2d|c2|c2d|m1|m2|m3|t2d|a2)-(standard|highmem|highcpu|ultramem)-(1|2|4|8|16|32|64|96|128)$", var.machine_type))
    error_message = "Machine type must be a valid Google Cloud Compute Engine machine type."
  }
}

variable "boot_disk_size" {
  description = "Boot disk size for compute instances in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.boot_disk_size >= 10 && var.boot_disk_size <= 65536
    error_message = "Boot disk size must be between 10 and 65536 GB."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type for compute instances"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Scheduling configuration variables
variable "max_delay_hours" {
  description = "Maximum delay hours for carbon-aware scheduling"
  type        = number
  default     = 8
  validation {
    condition     = var.max_delay_hours >= 1 && var.max_delay_hours <= 48
    error_message = "Max delay hours must be between 1 and 48 hours."
  }
}

variable "carbon_intensity_threshold" {
  description = "Carbon intensity threshold for scheduling decisions (kgCO2e)"
  type        = number
  default     = 0.5
  validation {
    condition     = var.carbon_intensity_threshold >= 0.0 && var.carbon_intensity_threshold <= 2.0
    error_message = "Carbon intensity threshold must be between 0.0 and 2.0 kgCO2e."
  }
}

# Monitoring configuration variables
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting for carbon metrics"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for carbon intensity alerts"
  type        = list(string)
  default     = []
}

variable "monitoring_dashboard_enabled" {
  description = "Create Cloud Monitoring dashboard for carbon-aware orchestration"
  type        = bool
  default     = true
}

# Security configuration variables
variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for network monitoring"
  type        = bool
  default     = false
}

variable "enable_private_google_access" {
  description = "Enable private Google access for VPC subnet"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "List of CIDR blocks allowed for ingress traffic"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_ingress_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress CIDRs must be valid CIDR notation."
  }
}

# Tagging and labeling variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose      = "carbon-aware-orchestration"
    managed-by   = "terraform"
    sustainability = "enabled"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens, with keys 1-63 chars and values 0-63 chars."
  }
}

# Cost optimization variables
variable "enable_preemptible_instances" {
  description = "Use preemptible instances for cost optimization where appropriate"
  type        = bool
  default     = true
}

variable "auto_scaling_min_replicas" {
  description = "Minimum number of replicas for auto-scaling resources"
  type        = number
  default     = 1
  validation {
    condition     = var.auto_scaling_min_replicas >= 0 && var.auto_scaling_min_replicas <= 100
    error_message = "Auto-scaling minimum replicas must be between 0 and 100."
  }
}

variable "auto_scaling_max_replicas" {
  description = "Maximum number of replicas for auto-scaling resources"
  type        = number
  default     = 10
  validation {
    condition     = var.auto_scaling_max_replicas >= 1 && var.auto_scaling_max_replicas <= 1000
    error_message = "Auto-scaling maximum replicas must be between 1 and 1000."
  }
}