# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID for weather-aware HPC infrastructure"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

# Weather API Configuration
variable "weather_api_key" {
  description = "Google Maps Platform Weather API key for real-time weather data"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.weather_api_key) > 0
    error_message = "Weather API key must be provided."
  }
}

variable "weather_monitoring_locations" {
  description = "Geographic locations for weather monitoring and scaling decisions"
  type = list(object({
    name      = string
    latitude  = number
    longitude = number
    region    = string
  }))
  default = [
    {
      name      = "us-east1"
      latitude  = 39.0458
      longitude = -76.6413
      region    = "us-east1"
    },
    {
      name      = "us-central1"
      latitude  = 41.2619
      longitude = -95.8608
      region    = "us-central1"
    },
    {
      name      = "us-west1"
      latitude  = 45.5152
      longitude = -122.6784
      region    = "us-west1"
    }
  ]
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name for the weather-aware HPC cluster"
  type        = string
  default     = "weather-hpc-cluster"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.cluster_name))
    error_message = "Cluster name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_machine_type" {
  description = "Machine type for HPC cluster compute nodes"
  type        = string
  default     = "c2-standard-60"
  validation {
    condition = contains([
      "c2-standard-4", "c2-standard-8", "c2-standard-16", "c2-standard-30", "c2-standard-60",
      "n2-standard-4", "n2-standard-8", "n2-standard-16", "n2-standard-32", "n2-standard-64",
      "n2-highmem-4", "n2-highmem-8", "n2-highmem-16", "n2-highmem-32", "n2-highmem-64"
    ], var.cluster_machine_type)
    error_message = "Machine type must be a valid compute-optimized or high-memory instance type."
  }
}

variable "cluster_max_nodes" {
  description = "Maximum number of compute nodes in the cluster"
  type        = number
  default     = 20
  validation {
    condition     = var.cluster_max_nodes >= 1 && var.cluster_max_nodes <= 100
    error_message = "Maximum nodes must be between 1 and 100."
  }
}

variable "cluster_min_nodes" {
  description = "Minimum number of compute nodes in the cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.cluster_min_nodes >= 0 && var.cluster_min_nodes <= 10
    error_message = "Minimum nodes must be between 0 and 10."
  }
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization in HPC cluster"
  type        = bool
  default     = true
}

# Storage Configuration
variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB for shared cluster storage"
  type        = number
  default     = 1024
  validation {
    condition     = var.filestore_capacity_gb >= 1024 && var.filestore_capacity_gb <= 65536
    error_message = "Filestore capacity must be between 1024 GB and 65536 GB."
  }
}

variable "filestore_tier" {
  description = "Filestore service tier for performance characteristics"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "PREMIUM", "BASIC_HDD", "BASIC_SSD"], var.filestore_tier)
    error_message = "Filestore tier must be one of: STANDARD, PREMIUM, BASIC_HDD, BASIC_SSD."
  }
}

# Cloud Function Configuration
variable "function_memory_mb" {
  description = "Memory allocation for weather processing Cloud Function"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for weather processing Cloud Function"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

# Monitoring Configuration
variable "weather_check_schedule" {
  description = "Cron schedule for regular weather data collection"
  type        = string
  default     = "*/15 * * * *"
  validation {
    condition     = can(regex("^(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)$", var.weather_check_schedule))
    error_message = "Weather check schedule must be a valid cron expression."
  }
}

variable "storm_monitor_schedule" {
  description = "Cron schedule for enhanced storm monitoring"
  type        = string
  default     = "*/5 * * * *"
  validation {
    condition     = can(regex("^(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)\\s+(\\*|[0-9,\\-/]+)$", var.storm_monitor_schedule))
    error_message = "Storm monitor schedule must be a valid cron expression."
  }
}

# Security Configuration
variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for secure access to cluster resources"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for cluster access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Network Configuration
variable "network_name" {
  description = "Name for the VPC network"
  type        = string
  default     = "weather-hpc-network"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    application = "weather-aware-hpc"
    managed-by  = "terraform"
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

# Cost Control
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 1000
  validation {
    condition     = var.budget_amount >= 100 && var.budget_amount <= 10000
    error_message = "Budget amount must be between $100 and $10,000."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [0.5, 0.8, 0.9, 1.0]
  validation {
    condition     = alltrue([for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 1])
    error_message = "Budget alert thresholds must be between 0.1 and 1.0."
  }
}