# ==================================================================================================
# TERRAFORM VARIABLES FOR AZURE DOCUMENT Q&A SOLUTION
# ==================================================================================================
# This file defines all configurable parameters for the Document Q&A infrastructure.
# Variables are organized by resource type with appropriate validation and descriptions.
# ==================================================================================================

# ==================================================================================================
# GENERAL CONFIGURATION VARIABLES
# ==================================================================================================

variable "location" {
  description = "The Azure region where resources will be deployed. Choose a region that supports Azure AI Search, OpenAI, and Functions."
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "South Central US", "West US 2", "West US 3",
      "Australia East", "Brazil South", "Canada Central", "North Europe", 
      "West Europe", "France Central", "Japan East", "UK South", "Sweden Central"
    ], var.location)
    error_message = "Location must be a region that supports Azure OpenAI Service. Please check Azure OpenAI regional availability."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 10
    error_message = "Environment name must be between 2 and 10 characters long."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group. If empty, a name will be generated automatically."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources. These will be merged with default tags."
  type        = map(string)
  default = {
    Project    = "Document-QA-System"
    Repository = "terraform-azure-recipes"
  }
}

# ==================================================================================================
# AZURE OPENAI SERVICE CONFIGURATION
# ==================================================================================================

variable "openai_location" {
  description = "Azure region for OpenAI Service deployment. Must support GPT-4o and text-embedding-3-large models."
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "North Central US", "South Central US", "West US", "West US 2", "West US 3",
      "Australia East", "Brazil South", "Canada Central", "North Europe", "West Europe", "France Central",
      "Japan East", "Norway East", "Sweden Central", "Switzerland North", "UK South"
    ], var.openai_location)
    error_message = "OpenAI location must be a region with Azure OpenAI availability. Check the latest regional availability guide."
  }
}

variable "openai_sku_name" {
  description = "SKU tier for Azure OpenAI Service. S0 provides standard performance and features."
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0. Other SKUs may not be available in all regions."
  }
}

variable "openai_public_network_access_enabled" {
  description = "Whether to allow public network access to the OpenAI service. Set to false for private endpoint access only."
  type        = bool
  default     = true
}

# ==================================================================================================
# AZURE AI SEARCH SERVICE CONFIGURATION
# ==================================================================================================

variable "search_service_sku" {
  description = "SKU tier for Azure AI Search Service. Basic tier includes semantic search capabilities required for this solution."
  type        = string
  default     = "basic"
  
  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3"], var.search_service_sku)
    error_message = "Search service SKU must be one of: free, basic, standard, standard2, standard3."
  }
}

variable "search_semantic_sku" {
  description = "Semantic search SKU for enhanced query understanding. Free tier provides basic semantic capabilities."
  type        = string
  default     = "free"
  
  validation {
    condition     = contains(["free", "standard"], var.search_semantic_sku)
    error_message = "Semantic search SKU must be either 'free' or 'standard'."
  }
}

variable "search_replica_count" {
  description = "Number of search replicas for high availability and query performance. Minimum 1, maximum varies by SKU."
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12
    error_message = "Search replica count must be between 1 and 12."
  }
}

variable "search_partition_count" {
  description = "Number of search partitions for data storage and indexing capacity. Must be 1 for free tier."
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 3, 4, 6, 12], var.search_partition_count)
    error_message = "Search partition count must be one of: 1, 2, 3, 4, 6, 12."
  }
}

variable "search_public_network_access_enabled" {
  description = "Whether to allow public network access to the search service. Required for indexer access to storage."
  type        = bool
  default     = true
}

variable "search_index_name" {
  description = "Name of the search index that will be created for document storage and querying."
  type        = string
  default     = "documents-index"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.search_index_name)) && length(var.search_index_name) <= 128
    error_message = "Search index name must contain only lowercase letters, numbers, and hyphens, and be no more than 128 characters."
  }
}

# ==================================================================================================
# STORAGE ACCOUNT CONFIGURATION
# ==================================================================================================

variable "storage_replication_type" {
  description = "Replication type for the storage account. LRS provides cost-effective local redundancy."
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "documents_container_name" {
  description = "Name of the blob container for storing documents to be indexed and searched."
  type        = string
  default     = "documents"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.documents_container_name))
    error_message = "Container name must be 3-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted blobs for recovery. Set to 1-365 days based on recovery requirements."
  type        = number
  default     = 7
  
  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "Blob delete retention days must be between 1 and 365."
  }
}

# ==================================================================================================
# AZURE FUNCTIONS CONFIGURATION
# ==================================================================================================

variable "function_app_sku_name" {
  description = "SKU name for the Function App Service Plan. Y1 provides consumption-based serverless scaling."
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "B1", "B2", "B3", 
      "S1", "S2", "S3", "P1v2", "P2v2", "P3v2"
    ], var.function_app_sku_name)
    error_message = "Function app SKU must be a valid Azure Functions or App Service plan SKU."
  }
}

variable "function_app_public_access_enabled" {
  description = "Whether to allow public network access to the Function App. Required for external API access."
  type        = bool
  default     = true
}

variable "python_version" {
  description = "Python runtime version for the Function App. 3.12 is the latest stable version with best performance."
  type        = string
  default     = "3.12"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11", "3.12"], var.python_version)
    error_message = "Python version must be one of the supported Azure Functions Python versions: 3.8, 3.9, 3.10, 3.11, 3.12."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS requests to the Function App API. Use ['*'] for all origins during development."
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

# ==================================================================================================
# MONITORING AND LOGGING CONFIGURATION
# ==================================================================================================

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace. Affects storage costs and compliance requirements."
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# ==================================================================================================
# ADVANCED CONFIGURATION VARIABLES
# ==================================================================================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure network access. Requires additional networking configuration."
  type        = bool
  default     = false
}

variable "virtual_network_subnet_id" {
  description = "Subnet ID for private endpoint deployment. Required when enable_private_endpoints is true."
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_private_endpoints == false || (var.enable_private_endpoints == true && var.virtual_network_subnet_id != "")
    error_message = "virtual_network_subnet_id is required when enable_private_endpoints is true."
  }
}

variable "search_allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access the search service. Empty list allows all IPs when public access is enabled."
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.search_allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., '192.168.1.0/24' or '10.0.0.1/32')."
  }
}

variable "openai_allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access the OpenAI service. Empty list allows all IPs when public access is enabled."
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.openai_allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., '192.168.1.0/24' or '10.0.0.1/32')."
  }
}

# ==================================================================================================
# COST OPTIMIZATION VARIABLES
# ==================================================================================================

variable "enable_auto_scaling" {
  description = "Enable automatic scaling for the Function App based on demand. Helps optimize costs while maintaining performance."
  type        = bool
  default     = true
}

variable "function_timeout_minutes" {
  description = "Function execution timeout in minutes. Affects cost and user experience for long-running queries."
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout_minutes >= 1 && var.function_timeout_minutes <= 10
    error_message = "Function timeout must be between 1 and 10 minutes for consumption plan."
  }
}

variable "daily_memory_quota_gb" {
  description = "Daily memory quota in GB for consumption plan Function Apps. Set to 0 for unlimited (higher cost)."
  type        = number
  default     = 0
  
  validation {
    condition     = var.daily_memory_quota_gb >= 0
    error_message = "Daily memory quota must be 0 (unlimited) or a positive number."
  }
}