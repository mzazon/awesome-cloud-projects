# Variable Definitions for Azure Notification Hubs Infrastructure
# These variables provide flexibility and customization for the notification hub deployment

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "Korea South", "Central India",
      "South India", "West India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name_prefix" {
  description = "Prefix for the resource group name that will be combined with a random suffix"
  type        = string
  default     = "rg-notifications"

  validation {
    condition     = length(var.resource_group_name_prefix) >= 1 && length(var.resource_group_name_prefix) <= 64
    error_message = "Resource group name prefix must be between 1 and 64 characters."
  }
}

variable "notification_hub_namespace_prefix" {
  description = "Prefix for the notification hub namespace name"
  type        = string
  default     = "nh-namespace"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.notification_hub_namespace_prefix))
    error_message = "Notification hub namespace prefix can only contain alphanumeric characters and hyphens."
  }
}

variable "notification_hub_name_prefix" {
  description = "Prefix for the notification hub name"
  type        = string
  default     = "notification-hub"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.notification_hub_name_prefix))
    error_message = "Notification hub name prefix can only contain alphanumeric characters and hyphens."
  }
}

variable "namespace_sku" {
  description = "SKU tier for the Notification Hub namespace"
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Basic", "Standard"], var.namespace_sku)
    error_message = "SKU must be one of: Free, Basic, Standard."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    environment = "demo"
    project     = "azure-notification-hubs"
  }

  validation {
    condition     = length(var.tags) <= 50
    error_message = "A maximum of 50 tags can be applied to Azure resources."
  }
}

variable "enable_test_notification" {
  description = "Whether to create and send a test notification during deployment"
  type        = bool
  default     = false
}