# Variable Definitions for Intelligent Image Content Discovery Infrastructure
# This file defines all configurable parameters for the image discovery system

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-image-discovery-demo"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West", "Korea Central",
      "Southeast Asia", "East Asia", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI services."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "imgdiscov"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Default access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

# AI Vision Service Configuration
variable "ai_vision_sku" {
  description = "SKU for Azure AI Vision service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S1"], var.ai_vision_sku)
    error_message = "AI Vision SKU must be either F0 (free) or S1 (standard)."
  }
}

variable "ai_vision_kind" {
  description = "Kind of cognitive services account for AI Vision"
  type        = string
  default     = "ComputerVision"
  
  validation {
    condition     = var.ai_vision_kind == "ComputerVision"
    error_message = "AI Vision kind must be ComputerVision."
  }
}

# AI Search Service Configuration
variable "search_sku" {
  description = "SKU for Azure AI Search service"
  type        = string
  default     = "basic"
  
  validation {
    condition = contains([
      "free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"
    ], var.search_sku)
    error_message = "Search SKU must be one of: free, basic, standard, standard2, standard3, storage_optimized_l1, storage_optimized_l2."
  }
}

variable "search_replica_count" {
  description = "Number of replicas for the search service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12
    error_message = "Search replica count must be between 1 and 12."
  }
}

variable "search_partition_count" {
  description = "Number of partitions for the search service"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 3, 4, 6, 12], var.search_partition_count)
    error_message = "Search partition count must be one of: 1, 2, 3, 4, 6, 12."
  }
}

# Function App Configuration
variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["dotnet", "java", "node", "python", "powershell"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: dotnet, java, node, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_runtime_version)
    error_message = "Python runtime version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "function_app_os_type" {
  description = "Operating system for the Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function app OS type must be either Linux or Windows."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

# Security and Networking Configuration
variable "enable_storage_public_access" {
  description = "Allow public access to storage account"
  type        = bool
  default     = false
}

variable "enable_https_only" {
  description = "Require HTTPS for storage account access"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# Resource Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "image-discovery"
    Purpose     = "intelligent-content-discovery"
    ManagedBy   = "terraform"
  }
}

# Search Index Configuration
variable "search_index_name" {
  description = "Name of the search index for image content"
  type        = string
  default     = "image-content-index"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.search_index_name))
    error_message = "Search index name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vector_dimensions" {
  description = "Number of dimensions for vector embeddings"
  type        = number
  default     = 1536
  
  validation {
    condition     = var.vector_dimensions > 0 && var.vector_dimensions <= 3072
    error_message = "Vector dimensions must be between 1 and 3072."
  }
}

# Blob Container Configuration
variable "image_container_name" {
  description = "Name of the blob container for image storage"
  type        = string
  default     = "images"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.image_container_name))
    error_message = "Container name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_access_type" {
  description = "Access level for the blob container"
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "blob", "container"], var.container_access_type)
    error_message = "Container access type must be one of: private, blob, container."
  }
}