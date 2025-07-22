# Core infrastructure variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-devinfra-demo"
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
      "Norway East", "Sweden Central", "Italy North", "Poland Central",
      "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia", "India Central", "India South",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "development"
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "engineering"
}

# DevCenter configuration variables
variable "devcenter_name" {
  description = "Name of the Azure DevCenter"
  type        = string
  default     = "dc-selfservice-demo"
}

variable "project_name" {
  description = "Name of the DevCenter project"
  type        = string
  default     = "proj-webapp-team"
}

variable "project_description" {
  description = "Description of the DevCenter project"
  type        = string
  default     = "Web application team development project"
}

# Network configuration variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "devbox_subnet_address_prefix" {
  description = "Address prefix for the Dev Box subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Dev Box configuration variables
variable "devbox_definition_name" {
  description = "Name of the Dev Box definition"
  type        = string
  default     = "VSEnterprise-8cpu-32gb"
}

variable "devbox_sku_name" {
  description = "SKU name for Dev Box compute"
  type        = string
  default     = "general_i_8c32gb256ssd_v2"
  
  validation {
    condition = contains([
      "general_i_8c32gb256ssd_v2", "general_i_16c64gb512ssd_v2",
      "general_i_32c128gb1024ssd_v2", "general_a_8c32gb256ssd_v2",
      "general_a_16c64gb512ssd_v2", "general_a_32c128gb1024ssd_v2"
    ], var.devbox_sku_name)
    error_message = "SKU name must be a valid Dev Box SKU."
  }
}

variable "devbox_pool_name" {
  description = "Name of the Dev Box pool"
  type        = string
  default     = "WebDevPool"
}

variable "enable_local_admin" {
  description = "Enable local administrator privileges on Dev Boxes"
  type        = bool
  default     = true
}

variable "hibernate_support" {
  description = "Enable hibernation support for Dev Boxes"
  type        = bool
  default     = true
}

# Auto-stop schedule configuration
variable "auto_stop_time" {
  description = "Time to automatically stop Dev Boxes (24-hour format)"
  type        = string
  default     = "19:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.auto_stop_time))
    error_message = "Auto stop time must be in HH:MM format (24-hour)."
  }
}

variable "auto_stop_timezone" {
  description = "Timezone for auto-stop schedule"
  type        = string
  default     = "Eastern Standard Time"
}

# Catalog configuration variables
variable "catalog_name" {
  description = "Name of the DevCenter catalog"
  type        = string
  default     = "QuickStartCatalog"
}

variable "catalog_repo_url" {
  description = "URL of the catalog repository"
  type        = string
  default     = "https://github.com/microsoft/devcenter-catalog.git"
}

variable "catalog_branch" {
  description = "Branch of the catalog repository"
  type        = string
  default     = "main"
}

variable "catalog_path" {
  description = "Path within the catalog repository"
  type        = string
  default     = "/Environment-Definitions"
}

# Environment type configuration
variable "environment_types" {
  description = "List of environment types to create"
  type        = list(string)
  default     = ["Development", "Staging"]
}

# Dev Box image configuration
variable "devbox_image_reference" {
  description = "Reference to the Dev Box image"
  type        = string
  default     = "MicrosoftWindowsDesktop_windows-ent-cpc_win11-22h2-ent-cpc-vs2022"
}

# User access configuration
variable "developer_user_principal_names" {
  description = "List of developer user principal names to grant access"
  type        = list(string)
  default     = []
}

variable "developer_group_object_ids" {
  description = "List of Azure AD group object IDs to grant access"
  type        = list(string)
  default     = []
}

# Resource naming configuration
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = null
}

variable "use_random_suffix" {
  description = "Generate a random suffix for resource names"
  type        = bool
  default     = true
}

# Tags configuration
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}