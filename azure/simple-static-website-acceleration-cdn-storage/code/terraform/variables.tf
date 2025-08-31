# Input Variables for Static Website Acceleration with CDN and Storage
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "Name of the Azure Resource Group where resources will be created"
  type        = string
  default     = "rg-static-website"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
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
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "India South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "storage_account_name_prefix" {
  description = "Prefix for the storage account name (will be combined with random suffix)"
  type        = string
  default     = "staticsite"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.storage_account_name_prefix))
    error_message = "Storage account name prefix must be 3-12 characters, lowercase letters and numbers only."
  }
}

variable "cdn_profile_name_prefix" {
  description = "Prefix for the CDN profile name (will be combined with random suffix)"
  type        = string
  default     = "cdn-profile"
  
  validation {
    condition     = length(var.cdn_profile_name_prefix) >= 1 && length(var.cdn_profile_name_prefix) <= 50
    error_message = "CDN profile name prefix must be between 1 and 50 characters."
  }
}

variable "cdn_endpoint_name_prefix" {
  description = "Prefix for the CDN endpoint name (will be combined with random suffix)"
  type        = string
  default     = "website"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,48}[a-zA-Z0-9]$", var.cdn_endpoint_name_prefix))
    error_message = "CDN endpoint name prefix must start and end with alphanumeric character, can contain hyphens, and be up to 50 characters."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Storage account access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either 'Hot' or 'Cool'."
  }
}

variable "cdn_sku" {
  description = "CDN profile SKU/pricing tier"
  type        = string
  default     = "Standard_Microsoft"
  
  validation {
    condition = contains([
      "Standard_Akamai", "Standard_Microsoft", "Standard_Verizon",
      "Premium_Verizon", "Standard_ChinaCdn", "Standard_955BandWidth_ChinaCdn"
    ], var.cdn_sku)
    error_message = "CDN SKU must be a valid Azure CDN pricing tier."
  }
}

variable "index_document" {
  description = "The index document name for the static website"
  type        = string
  default     = "index.html"
  
  validation {
    condition     = can(regex(".*\\.html?$", var.index_document))
    error_message = "Index document must be an HTML file with .html or .htm extension."
  }
}

variable "error_404_document" {
  description = "The 404 error document name for the static website"
  type        = string
  default     = "404.html"
  
  validation {
    condition     = can(regex(".*\\.html?$", var.error_404_document))
    error_message = "Error 404 document must be an HTML file with .html or .htm extension."
  }
}

variable "enable_cdn_compression" {
  description = "Enable compression on the CDN endpoint for better performance"
  type        = bool
  default     = true
}

variable "query_string_caching_behavior" {
  description = "Query string caching behavior for CDN endpoint"
  type        = string
  default     = "IgnoreQueryString"
  
  validation {
    condition = contains([
      "IgnoreQueryString", "BypassCaching", "UseQueryString"
    ], var.query_string_caching_behavior)
    error_message = "Query string caching behavior must be one of: IgnoreQueryString, BypassCaching, UseQueryString."
  }
}

variable "optimization_type" {
  description = "CDN endpoint optimization type for content delivery"
  type        = string
  default     = "GeneralWebDelivery"
  
  validation {
    condition = contains([
      "GeneralWebDelivery", "GeneralMediaStreaming", "VideoOnDemandMediaStreaming",
      "LargeFileDownload", "DynamicSiteAcceleration"
    ], var.optimization_type)
    error_message = "Optimization type must be a valid CDN optimization type."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    purpose     = "static-website"
    environment = "demo"
    recipe      = "simple-static-website-acceleration-cdn-storage"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

variable "create_sample_content" {
  description = "Whether to create and upload sample website content"
  type        = bool
  default     = true
}