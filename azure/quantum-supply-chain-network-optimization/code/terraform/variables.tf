# =============================================================================
# Variables for Azure Quantum Supply Chain Network Optimization
# =============================================================================

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US",
      "East US 2",
      "West US",
      "West US 2",
      "West US 3",
      "Central US",
      "South Central US",
      "North Central US",
      "West Central US",
      "Canada Central",
      "Canada East",
      "Brazil South",
      "UK South",
      "UK West",
      "West Europe",
      "North Europe",
      "France Central",
      "France South",
      "Germany West Central",
      "Germany North",
      "Switzerland North",
      "Switzerland West",
      "Norway East",
      "Norway West",
      "Sweden Central",
      "Sweden South",
      "Australia East",
      "Australia Southeast",
      "Australia Central",
      "Australia Central 2",
      "New Zealand North",
      "Southeast Asia",
      "East Asia",
      "Japan East",
      "Japan West",
      "Korea Central",
      "Korea South",
      "India Central",
      "India South",
      "India West",
      "South Africa North",
      "South Africa West"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "The environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "admin_email" {
  description = "Administrator email address for alert notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "The admin_email must be a valid email address."
  }
}

variable "quantum_workspace_name" {
  description = "Name of the Azure Quantum workspace (will be suffixed with random string)"
  type        = string
  default     = "quantum-workspace"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.quantum_workspace_name))
    error_message = "Quantum workspace name can only contain alphanumeric characters and hyphens."
  }
}

variable "digital_twins_instance_name" {
  description = "Name of the Azure Digital Twins instance (will be suffixed with random string)"
  type        = string
  default     = "dt-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.digital_twins_instance_name))
    error_message = "Digital Twins instance name can only contain alphanumeric characters and hyphens."
  }
}

variable "function_app_name" {
  description = "Name of the Azure Function App (will be suffixed with random string)"
  type        = string
  default     = "func-optimizer"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.function_app_name))
    error_message = "Function App name can only contain alphanumeric characters and hyphens."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account (will be suffixed with random string)"
  type        = string
  default     = "stsupplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.storage_account_name))
    error_message = "Storage account name can only contain alphanumeric characters."
  }
}

variable "cosmos_account_name" {
  description = "Name of the Cosmos DB account (will be suffixed with random string)"
  type        = string
  default     = "cosmos-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cosmos_account_name))
    error_message = "Cosmos DB account name can only contain alphanumeric characters and hyphens."
  }
}

variable "eventhub_namespace_name" {
  description = "Name of the Event Hub namespace (will be suffixed with random string)"
  type        = string
  default     = "eh-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.eventhub_namespace_name))
    error_message = "Event Hub namespace name can only contain alphanumeric characters and hyphens."
  }
}

variable "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job (will be suffixed with random string)"
  type        = string
  default     = "asa-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.stream_analytics_job_name))
    error_message = "Stream Analytics job name can only contain alphanumeric characters and hyphens."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (will be suffixed with random string)"
  type        = string
  default     = "la-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name can only contain alphanumeric characters and hyphens."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance (will be suffixed with random string)"
  type        = string
  default     = "insights-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.application_insights_name))
    error_message = "Application Insights name can only contain alphanumeric characters and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be suffixed with random string)"
  type        = string
  default     = "rg-quantum-supplychain"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_()]+$", var.resource_group_name))
    error_message = "Resource group name can only contain alphanumeric characters, hyphens, underscores, and parentheses."
  }
}

# =============================================================================
# Azure Quantum Configuration Variables
# =============================================================================

variable "quantum_providers" {
  description = "List of quantum providers to enable in the workspace"
  type        = list(string)
  default     = ["microsoft-qio", "1qbit"]
  
  validation {
    condition = alltrue([
      for provider in var.quantum_providers : contains([
        "microsoft-qio",
        "1qbit",
        "ionq",
        "quantinuum",
        "rigetti"
      ], provider)
    ])
    error_message = "Quantum providers must be from the supported list: microsoft-qio, 1qbit, ionq, quantinuum, rigetti."
  }
}

# =============================================================================
# Stream Analytics Configuration Variables
# =============================================================================

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 1
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Streaming units must be between 1 and 120."
  }
}

variable "eventhub_partition_count" {
  description = "Number of partitions for Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 1 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention period for Event Hub in days"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# =============================================================================
# Cosmos DB Configuration Variables
# =============================================================================

variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Eventual", "Session", "Strong", "BoundedStaleness", "ConsistentPrefix"], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, Session, Strong, BoundedStaleness, ConsistentPrefix."
  }
}

variable "cosmos_enable_serverless" {
  description = "Enable serverless mode for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmos_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = true
}

# =============================================================================
# Function App Configuration Variables
# =============================================================================

variable "function_app_python_version" {
  description = "Python version for Function App"
  type        = string
  default     = "3.9"
  
  validation {
    condition     = contains(["3.7", "3.8", "3.9", "3.10", "3.11"], var.function_app_python_version)
    error_message = "Python version must be one of: 3.7, 3.8, 3.9, 3.10, 3.11."
  }
}

variable "function_app_always_on" {
  description = "Keep Function App always on (not applicable for Consumption plan)"
  type        = bool
  default     = false
}

# =============================================================================
# Monitoring Configuration Variables
# =============================================================================

variable "log_analytics_retention_days" {
  description = "Log retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

# =============================================================================
# Supply Chain Configuration Variables
# =============================================================================

variable "supply_chain_suppliers" {
  description = "Configuration for supply chain suppliers"
  type = list(object({
    id            = string
    name          = string
    location      = string
    capacity      = number
    cost_per_unit = number
  }))
  default = [
    {
      id            = "supplier-001"
      name          = "Dallas Supplier"
      location      = "Dallas, TX"
      capacity      = 1000
      cost_per_unit = 15.50
    },
    {
      id            = "supplier-002"
      name          = "Chicago Supplier"
      location      = "Chicago, IL"
      capacity      = 1500
      cost_per_unit = 12.75
    }
  ]
}

variable "supply_chain_warehouses" {
  description = "Configuration for supply chain warehouses"
  type = list(object({
    id               = string
    name             = string
    location         = string
    storage_capacity = number
  }))
  default = [
    {
      id               = "warehouse-001"
      name             = "Atlanta Warehouse"
      location         = "Atlanta, GA"
      storage_capacity = 5000
    },
    {
      id               = "warehouse-002"
      name             = "Phoenix Warehouse"
      location         = "Phoenix, AZ"
      storage_capacity = 3000
    }
  ]
}

# =============================================================================
# Security Configuration Variables
# =============================================================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# =============================================================================
# Tagging Variables
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "project_name" {
  description = "Name of the project for tagging purposes"
  type        = string
  default     = "quantum-supply-chain-optimization"
}

variable "cost_center" {
  description = "Cost center for billing purposes"
  type        = string
  default     = "engineering"
}

variable "business_unit" {
  description = "Business unit owning the resources"
  type        = string
  default     = "supply-chain"
}