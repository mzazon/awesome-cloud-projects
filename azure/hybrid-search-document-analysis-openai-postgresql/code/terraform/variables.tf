# Core configuration variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-doc-analysis"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "South Africa North", "UAE North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "doc-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Azure OpenAI Service configuration
variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0."
  }
}

variable "openai_deployment_model" {
  description = "Model name for OpenAI deployment"
  type        = string
  default     = "text-embedding-ada-002"
}

variable "openai_deployment_version" {
  description = "Model version for OpenAI deployment"
  type        = string
  default     = "2"
}

variable "openai_deployment_capacity" {
  description = "Capacity for OpenAI deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 240
    error_message = "OpenAI deployment capacity must be between 1 and 240."
  }
}

# PostgreSQL configuration
variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be 11, 12, 13, 14, or 15."
  }
}

variable "postgresql_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "GP_Standard_D2s_v3"
  
  validation {
    condition     = can(regex("^(B_Standard_B|GP_Standard_D|MO_Standard_E)", var.postgresql_sku_name))
    error_message = "PostgreSQL SKU must be a valid flexible server SKU."
  }
}

variable "postgresql_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 131072
  
  validation {
    condition     = var.postgresql_storage_mb >= 20480 && var.postgresql_storage_mb <= 16777216
    error_message = "PostgreSQL storage must be between 20480 MB (20 GB) and 16777216 MB (16 TB)."
  }
}

variable "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "adminuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,62}$", var.postgresql_admin_username))
    error_message = "PostgreSQL admin username must be 3-63 characters, start with a letter, and contain only letters, numbers, and underscores."
  }
}

variable "postgresql_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  default     = "ComplexPassword123!"
  sensitive   = true
  
  validation {
    condition     = length(var.postgresql_admin_password) >= 8 && length(var.postgresql_admin_password) <= 128
    error_message = "PostgreSQL admin password must be between 8 and 128 characters."
  }
}

# Azure AI Search configuration
variable "search_sku" {
  description = "SKU for Azure AI Search service"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_sku)
    error_message = "Search SKU must be one of: free, basic, standard, standard2, standard3, storage_optimized_l1, storage_optimized_l2."
  }
}

variable "search_replica_count" {
  description = "Number of replicas for Azure AI Search"
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12
    error_message = "Search replica count must be between 1 and 12."
  }
}

variable "search_partition_count" {
  description = "Number of partitions for Azure AI Search"
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_partition_count >= 1 && var.search_partition_count <= 12
    error_message = "Search partition count must be between 1 and 12."
  }
}

# Azure Functions configuration
variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be a valid consumption or premium plan SKU."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be python, node, dotnet, or java."
  }
}

variable "function_app_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.9"
}

# Storage Account configuration
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
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Networking configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Monitoring and logging
variable "enable_monitoring" {
  description = "Enable monitoring and logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Tags
variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Purpose     = "Document Analysis"
    Solution    = "Hybrid Search"
    Technology  = "Azure OpenAI + PostgreSQL"
    Owner       = "Development Team"
  }
}