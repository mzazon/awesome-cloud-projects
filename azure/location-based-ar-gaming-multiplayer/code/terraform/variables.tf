# Core Infrastructure Variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "France Central",
      "France South", "UK South", "UK West", "Germany West Central", "Germany North",
      "Switzerland North", "Switzerland West", "Norway East", "Norway West",
      "Sweden Central", "Sweden South", "UAE North", "UAE Central", "South Africa North",
      "South Africa West", "Australia East", "Australia Southeast", "Australia Central",
      "Australia Central 2", "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "Korea South", "South India", "Central India", "West India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "argaming"
  
  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric and no more than 15 characters."
  }
}

# Gaming Platform Variables
variable "playfab_title_name" {
  description = "Display name for the PlayFab title"
  type        = string
  default     = "AR Gaming Experience"
  
  validation {
    condition     = length(var.playfab_title_name) <= 50
    error_message = "PlayFab title name must be 50 characters or less."
  }
}

variable "playfab_title_id" {
  description = "PlayFab Title ID (if existing, leave empty to create new)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "playfab_secret_key" {
  description = "PlayFab Secret Key (if existing, leave empty to create new)"
  type        = string
  default     = ""
  sensitive   = true
}

# Spatial Anchors Configuration
variable "spatial_anchors_account_name" {
  description = "Name for the Azure Spatial Anchors account"
  type        = string
  default     = ""
  
  validation {
    condition     = var.spatial_anchors_account_name == "" || (length(var.spatial_anchors_account_name) >= 3 && length(var.spatial_anchors_account_name) <= 90)
    error_message = "Spatial Anchors account name must be between 3 and 90 characters if specified."
  }
}

# Function App Configuration
variable "function_app_name" {
  description = "Name for the Azure Function App"
  type        = string
  default     = ""
  
  validation {
    condition     = var.function_app_name == "" || (length(var.function_app_name) >= 2 && length(var.function_app_name) <= 60)
    error_message = "Function App name must be between 2 and 60 characters if specified."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",           # Consumption
      "EP1", "EP2", "EP3",  # Elastic Premium
      "P1", "P2", "P3",     # Premium
      "S1", "S2", "S3",     # Standard
      "B1", "B2", "B3"      # Basic
    ], var.function_app_service_plan_sku)
    error_message = "Invalid Function App Service Plan SKU."
  }
}

variable "function_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "~4"
  
  validation {
    condition = contains([
      "~4", "~3"
    ], var.function_runtime_version)
    error_message = "Function runtime version must be ~4 or ~3."
  }
}

variable "function_dotnet_version" {
  description = ".NET version for Azure Functions"
  type        = string
  default     = "dotnet-isolated"
  
  validation {
    condition = contains([
      "dotnet-isolated", "dotnet"
    ], var.function_dotnet_version)
    error_message = "Function .NET version must be dotnet-isolated or dotnet."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains([
      "Standard", "Premium"
    ], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_account_replication_type)
    error_message = "Invalid storage account replication type."
  }
}

# Multiplayer Configuration
variable "multiplayer_max_players_per_location" {
  description = "Maximum number of players per location"
  type        = number
  default     = 8
  
  validation {
    condition     = var.multiplayer_max_players_per_location >= 2 && var.multiplayer_max_players_per_location <= 50
    error_message = "Max players per location must be between 2 and 50."
  }
}

variable "multiplayer_location_radius" {
  description = "Location radius in meters for multiplayer matching"
  type        = number
  default     = 100
  
  validation {
    condition     = var.multiplayer_location_radius >= 10 && var.multiplayer_location_radius <= 1000
    error_message = "Location radius must be between 10 and 1000 meters."
  }
}

variable "multiplayer_sync_frequency" {
  description = "Synchronization frequency in Hz for multiplayer"
  type        = number
  default     = 30
  
  validation {
    condition     = var.multiplayer_sync_frequency >= 10 && var.multiplayer_sync_frequency <= 60
    error_message = "Sync frequency must be between 10 and 60 Hz."
  }
}

# Security Configuration
variable "enable_mixed_reality_authentication" {
  description = "Enable Azure AD authentication for Mixed Reality services"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["https://*.playfab.com", "https://localhost:*"]
}

# Monitoring and Logging
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
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

# Event Grid Configuration
variable "enable_event_grid" {
  description = "Enable Event Grid for spatial anchor events"
  type        = bool
  default     = true
}

variable "event_grid_endpoint_type" {
  description = "Type of Event Grid endpoint"
  type        = string
  default     = "webhook"
  
  validation {
    condition = contains([
      "webhook", "eventhub", "storagequeue", "hybridconnection", "servicebustopic", "servicebusqueue"
    ], var.event_grid_endpoint_type)
    error_message = "Invalid Event Grid endpoint type."
  }
}

# Resource Tags
variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Environment   = "dev"
    Project      = "ar-gaming"
    Purpose      = "immersive-gaming"
    ManagedBy    = "terraform"
    CostCenter   = "engineering"
  }
}

# Advanced Configuration
variable "enable_advanced_features" {
  description = "Enable advanced features (additional cost)"
  type        = bool
  default     = false
}

variable "custom_domain" {
  description = "Custom domain for the Function App (optional)"
  type        = string
  default     = ""
}

variable "ssl_certificate_thumbprint" {
  description = "SSL certificate thumbprint for custom domain"
  type        = string
  default     = ""
}