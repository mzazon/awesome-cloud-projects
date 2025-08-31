# Variables for Azure RAG Knowledge Base Infrastructure

# Resource naming variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group. If empty, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]*$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name can only contain alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "France South", "Germany West Central", "Germany North", "Switzerland North",
      "Switzerland West", "Norway East", "Norway West", "Sweden Central", "Australia East", "Australia Southeast",
      "Australia Central", "Australia Central 2", "Japan East", "Japan West", "Korea Central", "Korea South",
      "India Central", "India South", "India West", "Southeast Asia", "East Asia", "South Africa North",
      "South Africa West", "UAE North", "UAE Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "storage_account_name" {
  description = "Name of the Azure Storage Account. If empty, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]*$", var.storage_account_name)) && length(var.storage_account_name) <= 24 || var.storage_account_name == ""
    error_message = "Storage account name must be between 3 and 24 characters, contain only lowercase letters and numbers."
  }
}

variable "search_service_name" {
  description = "Name of the Azure AI Search service. If empty, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.search_service_name)) && length(var.search_service_name) <= 60 || var.search_service_name == ""
    error_message = "Search service name must contain only lowercase letters, numbers, and hyphens, and be up to 60 characters."
  }
}

variable "function_app_name" {
  description = "Name of the Azure Function App. If empty, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.function_app_name)) || var.function_app_name == ""
    error_message = "Function app name can only contain alphanumeric characters and hyphens."
  }
}

variable "openai_service_name" {
  description = "Name of the Azure OpenAI service. If empty, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.openai_service_name)) || var.openai_service_name == ""
    error_message = "OpenAI service name can only contain alphanumeric characters and hyphens."
  }
}

# Azure AI Search configuration
variable "search_service_sku" {
  description = "SKU tier for Azure AI Search service"
  type        = string
  default     = "basic"
  
  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_service_sku)
    error_message = "Search service SKU must be one of: free, basic, standard, standard2, standard3, storage_optimized_l1, storage_optimized_l2."
  }
}

variable "search_replica_count" {
  description = "Number of replicas for Azure AI Search service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12
    error_message = "Search replica count must be between 1 and 12."
  }
}

variable "search_partition_count" {
  description = "Number of partitions for Azure AI Search service"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 3, 4, 6, 12], var.search_partition_count)
    error_message = "Search partition count must be one of: 1, 2, 3, 4, 6, 12."
  }
}

variable "search_public_access" {
  description = "Enable public network access for Azure AI Search service"
  type        = bool
  default     = true
}

variable "search_index_name" {
  description = "Name of the AI Search index for knowledge base documents"
  type        = string
  default     = "knowledge-base-index"
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.search_index_name))
    error_message = "Search index name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "search_datasource_name" {
  description = "Name of the AI Search data source for blob storage"
  type        = string
  default     = "blob-datasource"
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.search_datasource_name))
    error_message = "Search datasource name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "search_indexer_name" {
  description = "Name of the AI Search indexer"
  type        = string
  default     = "blob-indexer"
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.search_indexer_name))
    error_message = "Search indexer name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "search_indexer_schedule" {
  description = "Schedule interval for the AI Search indexer (ISO 8601 duration format)"
  type        = string
  default     = "PT15M"
  
  validation {
    condition     = can(regex("^PT[0-9]+[MH]$", var.search_indexer_schedule))
    error_message = "Indexer schedule must be in ISO 8601 duration format (e.g., PT15M for 15 minutes, PT1H for 1 hour)."
  }
}

# Azure OpenAI configuration
variable "openai_location" {
  description = "Azure region for OpenAI service (must support OpenAI)"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US", "North Central US", "South Central US",
      "West Europe", "France Central", "UK South", "Switzerland North", "Australia East", "Japan East",
      "Sweden Central", "Canada East"
    ], var.openai_location)
    error_message = "OpenAI location must be a region that supports Azure OpenAI service."
  }
}

variable "openai_sku" {
  description = "SKU for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "OpenAI SKU must be S0."
  }
}

variable "openai_public_access" {
  description = "Enable public network access for Azure OpenAI service"
  type        = bool
  default     = true
}

variable "openai_deployment_name" {
  description = "Name of the OpenAI model deployment"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]*$", var.openai_deployment_name))
    error_message = "OpenAI deployment name can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "openai_model_name" {
  description = "Name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-35-turbo", "text-embedding-ada-002"], var.openai_model_name)
    error_message = "OpenAI model name must be one of the supported models: gpt-4o, gpt-4, gpt-35-turbo, text-embedding-ada-002."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "openai_model_capacity" {
  description = "Capacity (tokens per minute) for the OpenAI model deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_model_capacity >= 1 && var.openai_model_capacity <= 1000
    error_message = "OpenAI model capacity must be between 1 and 1000."
  }
}

# Storage configuration
variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Function App configuration
variable "function_python_version" {
  description = "Python version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_python_version)
    error_message = "Function Python version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "function_cors_origins" {
  description = "List of allowed CORS origins for the Function App"
  type        = list(string)
  default     = ["*"]
}

# Sample documents configuration
variable "create_sample_documents" {
  description = "Whether to create sample documents for testing"
  type        = bool
  default     = true
}

variable "sample_document_1_content" {
  description = "Content for sample document 1"
  type        = string
  default     = <<-EOT
    Azure Functions is a serverless compute service that lets you run event-triggered code without having to explicitly provision or manage infrastructure. With Azure Functions, you pay only for the time your code runs.

    Key features include:
    - Automatic scaling based on demand
    - Built-in integration with other Azure services
    - Support for multiple programming languages
    - Pay-per-execution pricing model
  EOT
}

variable "sample_document_2_content" {
  description = "Content for sample document 2"
  type        = string
  default     = <<-EOT
    Azure AI Search is a cloud search service that gives developers infrastructure, APIs, and tools for building a rich search experience. Use it to create search solutions over private, heterogeneous content in web, mobile, and enterprise applications.

    Core capabilities:
    - Full-text search with AI enrichment
    - Vector search for semantic similarity
    - Hybrid search combining keyword and vector
    - Built-in AI skills for content extraction
  EOT
}

# Common tags for all resources
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "RAG Knowledge Base"
    Environment = "Demo"
    CreatedBy   = "Terraform"
  }
}