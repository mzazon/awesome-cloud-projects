# Variables for Azure Orbital and AI Services infrastructure

# Core Configuration Variables
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Israel Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Australia Central", "Australia Central 2", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Central India", "South India", "West India", "Jio India West"
    ], var.location)
    error_message = "The location must be a valid Azure region."
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

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "orbital-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Synapse Analytics Configuration
variable "synapse_sql_admin_username" {
  description = "SQL Administrator username for Synapse workspace"
  type        = string
  default     = "synadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,127}$", var.synapse_sql_admin_username))
    error_message = "Username must start with a letter and contain only letters, numbers, and underscores (3-128 characters)."
  }
}

variable "synapse_sql_admin_password" {
  description = "SQL Administrator password for Synapse workspace"
  type        = string
  sensitive   = true
  default     = "SecurePass123!"
  
  validation {
    condition = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{8,128}$", var.synapse_sql_admin_password))
    error_message = "Password must be 8-128 characters with at least one lowercase, uppercase, digit, and special character."
  }
}

variable "spark_pool_min_node_count" {
  description = "Minimum number of nodes for Spark pool"
  type        = number
  default     = 3
  
  validation {
    condition     = var.spark_pool_min_node_count >= 3 && var.spark_pool_min_node_count <= 200
    error_message = "Spark pool minimum node count must be between 3 and 200."
  }
}

variable "spark_pool_max_node_count" {
  description = "Maximum number of nodes for Spark pool"
  type        = number
  default     = 10
  
  validation {
    condition     = var.spark_pool_max_node_count >= 3 && var.spark_pool_max_node_count <= 200
    error_message = "Spark pool maximum node count must be between 3 and 200."
  }
}

variable "sql_pool_sku" {
  description = "SKU for Synapse SQL pool"
  type        = string
  default     = "DW100c"
  
  validation {
    condition = contains([
      "DW100c", "DW200c", "DW300c", "DW400c", "DW500c",
      "DW1000c", "DW1500c", "DW2000c", "DW2500c", "DW3000c"
    ], var.sql_pool_sku)
    error_message = "SQL pool SKU must be a valid Data Warehouse SKU."
  }
}

# Event Hubs Configuration
variable "eventhub_partition_count" {
  description = "Number of partitions for Event Hubs"
  type        = number
  default     = 8
  
  validation {
    condition     = var.eventhub_partition_count >= 1 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention period in days for Event Hubs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

variable "eventhub_throughput_units" {
  description = "Throughput units for Event Hubs namespace"
  type        = number
  default     = 10
  
  validation {
    condition     = var.eventhub_throughput_units >= 1 && var.eventhub_throughput_units <= 20
    error_message = "Event Hub throughput units must be between 1 and 20."
  }
}

# Cognitive Services Configuration
variable "cognitive_services_sku" {
  description = "SKU for Azure AI Services"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

variable "custom_vision_training_sku" {
  description = "SKU for Custom Vision training resource"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.custom_vision_training_sku)
    error_message = "Custom Vision training SKU must be F0 or S0."
  }
}

# Azure Maps Configuration
variable "maps_sku" {
  description = "SKU for Azure Maps account"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S0", "S1", "G2"], var.maps_sku)
    error_message = "Azure Maps SKU must be S0, S1, or G2."
  }
}

# Cosmos DB Configuration
variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be valid."
  }
}

variable "cosmos_throughput" {
  description = "Throughput for Cosmos DB containers"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Access tier for storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_tier)
    error_message = "Storage account tier must be Hot or Cool."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be a valid option."
  }
}

# Network Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9_.-]{1,128}$", key))
    ])
    error_message = "Tag keys must be valid Azure tag names (1-128 characters)."
  }
}

# Cost Management
variable "enable_auto_pause" {
  description = "Enable auto-pause for Spark pools to reduce costs"
  type        = bool
  default     = true
}

variable "auto_pause_delay_minutes" {
  description = "Auto-pause delay in minutes for Spark pools"
  type        = number
  default     = 15
  
  validation {
    condition     = var.auto_pause_delay_minutes >= 5 && var.auto_pause_delay_minutes <= 10080
    error_message = "Auto-pause delay must be between 5 and 10080 minutes."
  }
}

# Monitoring and Diagnostics
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}