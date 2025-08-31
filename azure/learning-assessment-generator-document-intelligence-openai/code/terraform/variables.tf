# Input variables for the Learning Assessment Generator infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Cognitive Services and OpenAI."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group to create or use"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "The name of the project, used as a prefix for resource names"
  type        = string
  default     = "learning-assessment"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose     = "learning-assessment"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "The performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Document Intelligence Configuration
variable "document_intelligence_sku" {
  description = "The SKU for the Document Intelligence service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be either F0 (free) or S0 (standard)."
  }
}

# Azure OpenAI Configuration
variable "openai_sku" {
  description = "The SKU for the Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "Azure OpenAI SKU must be S0 (standard)."
  }
}

variable "openai_model_name" {
  description = "The name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-35-turbo"], var.openai_model_name)
    error_message = "OpenAI model must be one of: gpt-4o, gpt-4, gpt-35-turbo."
  }
}

variable "openai_model_version" {
  description = "The version of the OpenAI model to deploy"
  type        = string
  default     = "2024-08-06"
}

variable "openai_deployment_capacity" {
  description = "The capacity (tokens per minute) for the OpenAI deployment"
  type        = number
  default     = 20
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 1000
    error_message = "OpenAI deployment capacity must be between 1 and 1000."
  }
}

# Cosmos DB Configuration
variable "cosmosdb_consistency_level" {
  description = "The consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmosdb_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmosdb_max_interval_in_seconds" {
  description = "The maximum lag time for BoundedStaleness consistency"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cosmosdb_max_interval_in_seconds >= 5 && var.cosmosdb_max_interval_in_seconds <= 86400
    error_message = "Cosmos DB max interval must be between 5 and 86400 seconds."
  }
}

variable "cosmosdb_max_staleness_prefix" {
  description = "The maximum number of stale requests for BoundedStaleness consistency"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.cosmosdb_max_staleness_prefix >= 10 && var.cosmosdb_max_staleness_prefix <= 2147483647
    error_message = "Cosmos DB max staleness prefix must be between 10 and 2147483647."
  }
}

# Function App Configuration
variable "function_app_runtime" {
  description = "The runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "dotnet", "node", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, dotnet, node, java."
  }
}

variable "function_app_runtime_version" {
  description = "The runtime version for the Function App"
  type        = string
  default     = "3.12"
}

variable "function_app_os_type" {
  description = "The operating system type for the Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either Linux or Windows."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "The type of Application Insights to create"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Security Configuration
variable "enable_managed_identity" {
  description = "Whether to enable managed identity for the Function App"
  type        = bool
  default     = true
}

variable "enable_https_only" {
  description = "Whether to enforce HTTPS-only access"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "The minimum TLS version for secure connections"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2."
  }
}

# Networking Configuration
variable "enable_public_network_access" {
  description = "Whether to enable public network access to resources"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Cost Management
variable "enable_auto_scale" {
  description = "Whether to enable auto-scaling for the Function App"
  type        = bool
  default     = true
}

variable "max_elastic_worker_count" {
  description = "The maximum number of elastic workers"
  type        = number
  default     = 20
  
  validation {
    condition     = var.max_elastic_worker_count >= 1 && var.max_elastic_worker_count <= 100
    error_message = "Maximum elastic worker count must be between 1 and 100."
  }
}