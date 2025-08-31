# Resource Group Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group for content moderation resources"
  type        = string
  default     = "rg-content-moderation"
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 64
    error_message = "Resource group name must be between 3 and 64 characters."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Central India", "South India", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Naming and Tagging Variables
variable "environment" {
  description = "Environment tag for resources (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for consistent resource naming"
  type        = string
  default     = "contentmod"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Content Safety Service Variables
variable "content_safety_sku" {
  description = "SKU for Azure AI Content Safety service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.content_safety_sku)
    error_message = "Content Safety SKU must be F0 (free) or S0 (standard)."
  }
}

variable "content_safety_custom_subdomain" {
  description = "Custom subdomain name for Content Safety endpoint (auto-generated if empty)"
  type        = string
  default     = ""
}

# Storage Account Variables
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

variable "content_container_name" {
  description = "Name of the blob container for content uploads"
  type        = string
  default     = "content-uploads"
  
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.content_container_name))
    error_message = "Container name must be lowercase alphanumeric with hyphens, 3-63 characters."
  }
}

# Logic App Configuration Variables
variable "logic_app_plan_sku" {
  description = "SKU for the Logic App (WS1 for Consumption, WS2 for Standard)"
  type        = string
  default     = "WS1"
  
  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_plan_sku)
    error_message = "Logic App SKU must be WS1, WS2, or WS3."
  }
}

variable "enable_logic_app" {
  description = "Whether to enable the Logic App workflow immediately after deployment"
  type        = bool
  default     = true
}

# Content Moderation Configuration Variables
variable "moderation_severity_thresholds" {
  description = "Severity thresholds for content moderation decisions"
  type = object({
    auto_approve_max_severity = number
    review_min_severity      = number
    auto_reject_min_severity = number
  })
  default = {
    auto_approve_max_severity = 0  # Auto-approve content with severity 0 (safe)
    review_min_severity      = 2  # Flag for review content with severity 2-3 (medium risk)
    auto_reject_min_severity = 4  # Auto-reject content with severity 4+ (high risk)
  }
  
  validation {
    condition = (
      var.moderation_severity_thresholds.auto_approve_max_severity >= 0 &&
      var.moderation_severity_thresholds.auto_approve_max_severity < var.moderation_severity_thresholds.review_min_severity &&
      var.moderation_severity_thresholds.review_min_severity < var.moderation_severity_thresholds.auto_reject_min_severity &&
      var.moderation_severity_thresholds.auto_reject_min_severity <= 6
    )
    error_message = "Severity thresholds must be in ascending order (0-6) with auto_approve < review < auto_reject."
  }
}

variable "notification_email" {
  description = "Email address for moderation notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Security and Compliance Variables
variable "enable_https_only" {
  description = "Enforce HTTPS-only access for storage account"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "enable_storage_logging" {
  description = "Enable diagnostic logging for storage account"
  type        = bool
  default     = true
}

# Cost Management Variables
variable "enable_lifecycle_management" {
  description = "Enable lifecycle management policies for storage account"
  type        = bool
  default     = true
}

variable "lifecycle_days_to_cool" {
  description = "Number of days before moving blobs to cool tier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_days_to_cool >= 1
    error_message = "Lifecycle days to cool must be at least 1 day."
  }
}

variable "lifecycle_days_to_archive" {
  description = "Number of days before moving blobs to archive tier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.lifecycle_days_to_archive >= var.lifecycle_days_to_cool
    error_message = "Lifecycle days to archive must be greater than or equal to days to cool."
  }
}