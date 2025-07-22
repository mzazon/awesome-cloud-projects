# Variables for Azure Quantum Financial Trading Algorithm Infrastructure
# These variables allow customization of the quantum-enhanced financial trading solution

# General Configuration Variables
variable "location" {
  description = "Azure region for deploying resources. Must support Azure Quantum and Elastic SAN services."
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "West Europe", "Southeast Asia"
    ], var.location)
    error_message = "Location must be a region that supports Azure Quantum services."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,15}$", var.environment))
    error_message = "Environment must be 3-15 characters, lowercase alphanumeric only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated automatically."
  type        = string
  default     = ""
}

# Financial Trading Configuration
variable "risk_tolerance" {
  description = "Risk tolerance level for portfolio optimization (0.0 = risk-averse, 1.0 = risk-seeking)"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.risk_tolerance >= 0.0 && var.risk_tolerance <= 1.0
    error_message = "Risk tolerance must be between 0.0 and 1.0."
  }
}

variable "portfolio_size_limit" {
  description = "Maximum number of assets in portfolio optimization"
  type        = number
  default     = 100
  
  validation {
    condition     = var.portfolio_size_limit >= 10 && var.portfolio_size_limit <= 500
    error_message = "Portfolio size limit must be between 10 and 500 assets."
  }
}

# Azure Elastic SAN Configuration
variable "elastic_san_base_size_tib" {
  description = "Base size of Azure Elastic SAN in TiB for high-performance market data storage"
  type        = number
  default     = 10
  
  validation {
    condition     = var.elastic_san_base_size_tib >= 1 && var.elastic_san_base_size_tib <= 100
    error_message = "Elastic SAN base size must be between 1 and 100 TiB."
  }
}

variable "elastic_san_extended_capacity_tib" {
  description = "Extended capacity of Azure Elastic SAN in TiB for burst workloads"
  type        = number
  default     = 5
  
  validation {
    condition     = var.elastic_san_extended_capacity_tib >= 0 && var.elastic_san_extended_capacity_tib <= 50
    error_message = "Elastic SAN extended capacity must be between 0 and 50 TiB."
  }
}

variable "market_data_volume_size_gib" {
  description = "Size of market data volume in GiB for real-time trading data"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.market_data_volume_size_gib >= 100 && var.market_data_volume_size_gib <= 5000
    error_message = "Market data volume size must be between 100 and 5000 GiB."
  }
}

# Azure Quantum Configuration
variable "quantum_providers" {
  description = "List of quantum providers to enable in the workspace"
  type        = list(string)
  default     = ["microsoft", "ionq"]
  
  validation {
    condition = alltrue([
      for provider in var.quantum_providers : contains(["microsoft", "ionq", "quantinuum"], provider)
    ])
    error_message = "Quantum providers must be from the list: microsoft, ionq, quantinuum."
  }
}

variable "quantum_workspace_storage_sku" {
  description = "Storage account SKU for Quantum workspace"
  type        = string
  default     = "Standard_LRS"
  
  validation {
    condition = contains([
      "Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS"
    ], var.quantum_workspace_storage_sku)
    error_message = "Storage SKU must be one of: Standard_LRS, Standard_GRS, Standard_RAGRS, Premium_LRS."
  }
}

# Azure Machine Learning Configuration
variable "ml_compute_instances" {
  description = "Configuration for ML compute instances"
  type = object({
    min_nodes = number
    max_nodes = number
    vm_size   = string
  })
  default = {
    min_nodes = 0
    max_nodes = 10
    vm_size   = "Standard_DS3_v2"
  }
  
  validation {
    condition = var.ml_compute_instances.min_nodes >= 0 && 
                var.ml_compute_instances.max_nodes >= var.ml_compute_instances.min_nodes &&
                var.ml_compute_instances.max_nodes <= 20
    error_message = "ML compute configuration must have valid node counts (0 <= min <= max <= 20)."
  }
}

# Real-time Data Processing Configuration
variable "event_hub_throughput_units" {
  description = "Number of throughput units for Event Hub (market data streaming)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.event_hub_throughput_units >= 1 && var.event_hub_throughput_units <= 20
    error_message = "Event Hub throughput units must be between 1 and 20."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 3
  
  validation {
    condition = contains([1, 3, 6, 12, 18, 24, 30, 36, 42, 48], var.stream_analytics_streaming_units)
    error_message = "Stream Analytics streaming units must be one of: 1, 3, 6, 12, 18, 24, 30, 36, 42, 48."
  }
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for advanced monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access quantum and ML resources"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = true
}

# Data Factory Configuration
variable "data_factory_git_config" {
  description = "Git configuration for Data Factory source control"
  type = object({
    enabled           = bool
    repository_url    = string
    collaboration_branch = string
    root_folder       = string
  })
  default = {
    enabled           = false
    repository_url    = ""
    collaboration_branch = ""
    root_folder       = ""
  }
}

# Cost Management
variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown of compute resources during off-hours"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Time to automatically shutdown compute resources (24-hour format, e.g., 2100)"
  type        = string
  default     = "2100"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto shutdown time must be in 24-hour format (HHMM)."
  }
}

# Backup and Disaster Recovery
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "enable_geo_redundancy" {
  description = "Enable geo-redundant storage and backups"
  type        = bool
  default     = true
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}