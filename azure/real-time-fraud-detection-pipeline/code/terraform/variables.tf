# Variables for Azure Real-Time Fraud Detection Pipeline

variable "resource_group_name" {
  description = "Name of the resource group for all fraud detection resources"
  type        = string
  default     = "rg-fraud-detection"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "India Central", "India South", "India West",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "fraud-detection"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, end with letter or number, and contain only letters, numbers, and hyphens."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

# Event Hubs Configuration
variable "eventhub_namespace_sku" {
  description = "SKU for Event Hubs namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_namespace_sku)
    error_message = "Event Hub namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 2 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 2 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention period in days for Event Hub"
  type        = number
  default     = 7
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

variable "eventhub_max_throughput_units" {
  description = "Maximum throughput units for Event Hubs namespace"
  type        = number
  default     = 20
  
  validation {
    condition     = var.eventhub_max_throughput_units >= 1 && var.eventhub_max_throughput_units <= 40
    error_message = "Maximum throughput units must be between 1 and 40."
  }
}

# Stream Analytics Configuration
variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 3
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Streaming units must be between 1 and 120."
  }
}

variable "stream_analytics_compatibility_level" {
  description = "Compatibility level for Stream Analytics job"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.stream_analytics_compatibility_level)
    error_message = "Compatibility level must be 1.0, 1.1, or 1.2."
  }
}

# Machine Learning Configuration
variable "ml_compute_instance_size" {
  description = "Size of the ML compute instance"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2",
      "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3"
    ], var.ml_compute_instance_size)
    error_message = "ML compute instance size must be a valid Azure VM size."
  }
}

# Cosmos DB Configuration
variable "cosmosdb_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmosdb_consistency_level)
    error_message = "Cosmos DB consistency level must be valid."
  }
}

variable "cosmosdb_throughput" {
  description = "Throughput for Cosmos DB containers (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmosdb_throughput >= 400 && var.cosmosdb_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "cosmosdb_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmosdb_enable_multiple_write_locations" {
  description = "Enable multiple write locations for Cosmos DB"
  type        = bool
  default     = false
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"
    ], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be valid."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be ~3 or ~4."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be valid."
  }
}

# Monitoring and Alerting Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_log_analytics" {
  description = "Enable Log Analytics workspace"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Log retention period in days for Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for firewall rules"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner of the resources for tagging"
  type        = string
  default     = ""
}