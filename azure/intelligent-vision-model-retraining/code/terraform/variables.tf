# Variables for Azure Custom Vision and Logic Apps automation infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "India Central", "India South", "India West",
      "Southeast Asia", "East Asia", "China East 2", "China North 2"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cv-retraining"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if it doesn't exist)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Storage account access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Access tier must be either Hot or Cool."
  }
}

variable "custom_vision_sku" {
  description = "SKU for Azure Custom Vision service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.custom_vision_sku)
    error_message = "Custom Vision SKU must be either F0 (free) or S0 (standard)."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "CapacityReservation"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "logic_app_trigger_frequency" {
  description = "Frequency for Logic App blob trigger (Minute, Hour, Day)"
  type        = string
  default     = "Minute"
  
  validation {
    condition     = contains(["Minute", "Hour", "Day"], var.logic_app_trigger_frequency)
    error_message = "Logic App trigger frequency must be Minute, Hour, or Day."
  }
}

variable "logic_app_trigger_interval" {
  description = "Interval for Logic App blob trigger"
  type        = number
  default     = 5
  
  validation {
    condition     = var.logic_app_trigger_interval > 0 && var.logic_app_trigger_interval <= 1000
    error_message = "Logic App trigger interval must be between 1 and 1000."
  }
}

variable "training_images_max_file_count" {
  description = "Maximum number of files to process in batch for training"
  type        = number
  default     = 10
  
  validation {
    condition     = var.training_images_max_file_count > 0 && var.training_images_max_file_count <= 100
    error_message = "Max file count must be between 1 and 100."
  }
}

variable "custom_vision_project_type" {
  description = "Custom Vision project type (Classification or ObjectDetection)"
  type        = string
  default     = "Classification"
  
  validation {
    condition     = contains(["Classification", "ObjectDetection"], var.custom_vision_project_type)
    error_message = "Custom Vision project type must be Classification or ObjectDetection."
  }
}

variable "custom_vision_classification_type" {
  description = "Classification type for Custom Vision (Multiclass or Multilabel)"
  type        = string
  default     = "Multiclass"
  
  validation {
    condition     = contains(["Multiclass", "Multilabel"], var.custom_vision_classification_type)
    error_message = "Classification type must be Multiclass or Multilabel."
  }
}

variable "alert_evaluation_frequency" {
  description = "Frequency for alert rule evaluation (ISO 8601 duration format)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = can(regex("^PT[0-9]+[MH]$", var.alert_evaluation_frequency))
    error_message = "Alert evaluation frequency must be in ISO 8601 duration format (e.g., PT5M, PT1H)."
  }
}

variable "alert_window_size" {
  description = "Window size for alert rule evaluation (ISO 8601 duration format)"
  type        = string
  default     = "PT15M"
  
  validation {
    condition     = can(regex("^PT[0-9]+[MH]$", var.alert_window_size))
    error_message = "Alert window size must be in ISO 8601 duration format (e.g., PT15M, PT1H)."
  }
}

variable "notification_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_public_access" {
  description = "Enable public access for storage account (not recommended for production)"
  type        = bool
  default     = false
}

variable "enable_blob_versioning" {
  description = "Enable blob versioning for storage account"
  type        = bool
  default     = true
}

variable "enable_soft_delete" {
  description = "Enable soft delete for blobs"
  type        = bool
  default     = true
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "Blob soft delete retention must be between 1 and 365 days."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted containers"
  type        = number
  default     = 7
  
  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "Container soft delete retention must be between 1 and 365 days."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for advanced monitoring"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "cv-retraining"
    Purpose     = "ml-automation"
    ManagedBy   = "terraform"
  }
}