# ==============================================================================
# CORE CONFIGURATION VARIABLES
# ==============================================================================

variable "resource_group_name" {
  description = "Name of the resource group for the industrial training platform"
  type        = string
  default     = "rg-industrial-training"
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "North Europe", "West Europe", 
      "Southeast Asia", "Australia East"
    ], var.location)
    error_message = "Location must be a region that supports Azure Mixed Reality services."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "industrial-training"
}

# ==============================================================================
# AZURE REMOTE RENDERING VARIABLES
# ==============================================================================

variable "remote_rendering_account_name" {
  description = "Name for the Azure Remote Rendering account"
  type        = string
  default     = ""
}

variable "remote_rendering_sku_name" {
  description = "SKU name for Azure Remote Rendering service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1"], var.remote_rendering_sku_name)
    error_message = "Remote Rendering SKU must be S1."
  }
}

# ==============================================================================
# AZURE SPATIAL ANCHORS VARIABLES
# ==============================================================================

variable "spatial_anchors_account_name" {
  description = "Name for the Azure Spatial Anchors account"
  type        = string
  default     = ""
}

variable "spatial_anchors_sku_name" {
  description = "SKU name for Azure Spatial Anchors service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1"], var.spatial_anchors_sku_name)
    error_message = "Spatial Anchors SKU must be S1."
  }
}

# ==============================================================================
# AZURE STORAGE VARIABLES
# ==============================================================================

variable "storage_account_name" {
  description = "Name for the Azure Storage account (will be made unique)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

# ==============================================================================
# AZURE ACTIVE DIRECTORY VARIABLES
# ==============================================================================

variable "ad_application_name" {
  description = "Name for the Azure AD application"
  type        = string
  default     = ""
}

variable "ad_application_sign_in_audience" {
  description = "Sign-in audience for the Azure AD application"
  type        = string
  default     = "AzureADMyOrg"
  
  validation {
    condition = contains([
      "AzureADMyOrg", "AzureADMultipleOrgs", 
      "AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount"
    ], var.ad_application_sign_in_audience)
    error_message = "Sign-in audience must be a valid Azure AD audience type."
  }
}

# ==============================================================================
# TRAINING PLATFORM CONFIGURATION VARIABLES
# ==============================================================================

variable "training_platform_settings" {
  description = "Configuration settings for the training platform"
  type = object({
    max_concurrent_users = number
    session_timeout      = number
    rendering_quality    = string
    enable_collaboration = bool
  })
  default = {
    max_concurrent_users = 10
    session_timeout      = 3600
    rendering_quality    = "high"
    enable_collaboration = true
  }
  
  validation {
    condition     = contains(["low", "medium", "high"], var.training_platform_settings.rendering_quality)
    error_message = "Rendering quality must be low, medium, or high."
  }
  
  validation {
    condition     = var.training_platform_settings.max_concurrent_users >= 1 && var.training_platform_settings.max_concurrent_users <= 50
    error_message = "Max concurrent users must be between 1 and 50."
  }
  
  validation {
    condition     = var.training_platform_settings.session_timeout >= 300 && var.training_platform_settings.session_timeout <= 14400
    error_message = "Session timeout must be between 300 and 14400 seconds."
  }
}

variable "model_settings" {
  description = "Configuration settings for 3D models"
  type = object({
    lod_levels      = list(string)
    texture_quality = string
    enable_physics  = bool
    enable_interaction = bool
  })
  default = {
    lod_levels      = ["high", "medium", "low"]
    texture_quality = "high"
    enable_physics  = true
    enable_interaction = true
  }
  
  validation {
    condition     = contains(["low", "medium", "high"], var.model_settings.texture_quality)
    error_message = "Texture quality must be low, medium, or high."
  }
}

variable "spatial_settings" {
  description = "Configuration settings for spatial anchoring"
  type = object({
    anchor_persistence = bool
    room_scale        = bool
    tracking_accuracy = string
    enable_world_mapping = bool
  })
  default = {
    anchor_persistence = true
    room_scale        = true
    tracking_accuracy = "high"
    enable_world_mapping = true
  }
  
  validation {
    condition     = contains(["low", "medium", "high"], var.spatial_settings.tracking_accuracy)
    error_message = "Tracking accuracy must be low, medium, or high."
  }
}

# ==============================================================================
# TAGGING VARIABLES
# ==============================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "mixed-reality-training"
    Purpose     = "industrial-training"
    Owner       = "platform-team"
  }
}

# ==============================================================================
# SECURITY VARIABLES
# ==============================================================================

variable "enable_https_traffic_only" {
  description = "Enable HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "enable_storage_logging" {
  description = "Enable logging for storage account operations"
  type        = bool
  default     = true
}

variable "storage_delete_retention_days" {
  description = "Number of days to retain deleted blobs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.storage_delete_retention_days >= 1 && var.storage_delete_retention_days <= 365
    error_message = "Delete retention days must be between 1 and 365."
  }
}

# ==============================================================================
# NETWORKING VARIABLES
# ==============================================================================

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access storage account"
  type        = list(string)
  default     = []
}

variable "enable_public_network_access" {
  description = "Enable public network access to storage account"
  type        = bool
  default     = true
}