# Input variables for the gaming backend infrastructure

variable "project_id" {
  description = "The Google Cloud project ID for the gaming backend"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be valid Google Cloud project identifier."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "redis_memory_size_gb" {
  description = "Memory size in GB for the Redis instance"
  type        = number
  default     = 1
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_tier" {
  description = "Redis tier for availability requirements"
  type        = string
  default     = "STANDARD_HA"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either BASIC or STANDARD_HA."
  }
}

variable "redis_version" {
  description = "Redis version for the Memorystore instance"
  type        = string
  default     = "REDIS_7_0"
  validation {
    condition     = contains(["REDIS_6_X", "REDIS_7_0"], var.redis_version)
    error_message = "Redis version must be either REDIS_6_X or REDIS_7_0."
  }
}

variable "game_server_machine_type" {
  description = "Machine type for game server instances"
  type        = string
  default     = "n2-standard-2"
  validation {
    condition = can(regex("^[a-z0-9]+-[a-z0-9]+-[0-9]+$", var.game_server_machine_type))
    error_message = "Machine type must be a valid Google Compute Engine machine type."
  }
}

variable "game_server_disk_size_gb" {
  description = "Boot disk size in GB for game server instances"
  type        = number
  default     = 20
  validation {
    condition     = var.game_server_disk_size_gb >= 10 && var.game_server_disk_size_gb <= 100
    error_message = "Disk size must be between 10 and 100 GB."
  }
}

variable "min_replicas" {
  description = "Minimum number of game server replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.min_replicas >= 1 && var.min_replicas <= 10
    error_message = "Minimum replicas must be between 1 and 10."
  }
}

variable "max_replicas" {
  description = "Maximum number of game server replicas"
  type        = number
  default     = 5
  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 100
    error_message = "Maximum replicas must be between 1 and 100."
  }
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for static asset delivery"
  type        = bool
  default     = true
}

variable "ssl_domains" {
  description = "List of domains for managed SSL certificates"
  type        = list(string)
  default     = []
  validation {
    condition = length(var.ssl_domains) == 0 || alltrue([
      for domain in var.ssl_domains : can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", domain))
    ])
    error_message = "All SSL domains must be valid domain names."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "gaming-backend"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "network_tier" {
  description = "Network tier for external IP addresses"
  type        = string
  default     = "PREMIUM"
  validation {
    condition     = contains(["PREMIUM", "STANDARD"], var.network_tier)
    error_message = "Network tier must be either PREMIUM or STANDARD."
  }
}

variable "storage_class" {
  description = "Storage class for the game assets bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}