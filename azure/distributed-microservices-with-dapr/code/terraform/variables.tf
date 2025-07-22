# General Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-dapr-microservices"
}

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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "dapr-microservices"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters long and contain only alphanumeric characters and hyphens."
  }
}

# Container Apps Configuration
variable "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  type        = string
  default     = "aca-env-dapr"
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  type        = string
  default     = "law-dapr-microservices"
}

variable "log_retention_in_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Service Bus Configuration
variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "service_bus_topic_name" {
  description = "Name of the Service Bus topic for order events"
  type        = string
  default     = "orders"
}

# Cosmos DB Configuration
variable "cosmos_db_offer_type" {
  description = "Offer type for Cosmos DB account"
  type        = string
  default     = "Standard"
}

variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB account"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmos_db_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database"
  type        = string
  default     = "daprstate"
}

variable "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container"
  type        = string
  default     = "statestore"
}

variable "cosmos_db_partition_key_path" {
  description = "Partition key path for Cosmos DB container"
  type        = string
  default     = "/partitionKey"
}

# Key Vault Configuration
variable "key_vault_sku_name" {
  description = "SKU name for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Container App Configuration
variable "order_service_name" {
  description = "Name of the order service container app"
  type        = string
  default     = "order-service"
}

variable "inventory_service_name" {
  description = "Name of the inventory service container app"
  type        = string
  default     = "inventory-service"
}

variable "container_image" {
  description = "Container image for microservices"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "container_cpu" {
  description = "CPU allocation for container apps"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.container_cpu >= 0.25 && var.container_cpu <= 4.0
    error_message = "Container CPU must be between 0.25 and 4.0."
  }
}

variable "container_memory" {
  description = "Memory allocation for container apps (in Gi)"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.container_memory))
    error_message = "Container memory must be in format like '1.0Gi'."
  }
}

variable "min_replicas" {
  description = "Minimum number of replicas for container apps"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 1000
    error_message = "Minimum replicas must be between 0 and 1000."
  }
}

variable "max_replicas" {
  description = "Maximum number of replicas for container apps"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 1000
    error_message = "Maximum replicas must be between 1 and 1000."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "insights-dapr-demo"
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "microservices-demo"
    Environment = "development"
    Project     = "dapr-container-apps"
    ManagedBy   = "terraform"
  }
}