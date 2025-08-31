# Variables for Azure Maps Store Locator Infrastructure
# This file defines configurable parameters for the store locator deployment

variable "resource_group_name" {
  description = "The name of the resource group for store locator resources"
  type        = string
  default     = "rg-storemaps"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

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
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region where Azure Maps is available."
  }
}

variable "maps_account_name" {
  description = "The name of the Azure Maps account (will be made unique with random suffix)"
  type        = string
  default     = "mapstore"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.maps_account_name))
    error_message = "Maps account name must contain only alphanumeric characters."
  }
}

variable "maps_sku_name" {
  description = "The pricing tier (SKU) for the Azure Maps account"
  type        = string
  default     = "G2"
  
  validation {
    condition     = contains(["G2"], var.maps_sku_name)
    error_message = "SKU must be G2 (Gen2 pricing tier). Gen1 SKUs (S0, S1) are deprecated."
  }
}

variable "local_authentication_enabled" {
  description = "Enable local authentication (subscription keys) for Azure Maps account"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "enable_system_managed_identity" {
  description = "Enable system-assigned managed identity for the Azure Maps account"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A mapping of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "Recipe"
    Application = "Store Locator"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
  
  validation {
    condition     = can(var.tags["Purpose"])
    error_message = "Tags must include a 'Purpose' key."
  }
}

variable "generate_random_suffix" {
  description = "Generate a random suffix for resource names to ensure uniqueness"
  type        = bool
  default     = true
}