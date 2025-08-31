# Input Variables for Event Grid and Functions Infrastructure
# These variables allow customization of the deployed resources

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "UK South", "UK West", "West Europe",
      "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East",
      "Japan West", "Korea Central", "Southeast Asia",
      "East Asia", "Central India", "South India", "West India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "recipe"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,8}$", var.resource_name_prefix))
    error_message = "Resource name prefix must be 2-8 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Azure Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java", "powershell"], var.function_app_runtime)
    error_message = "Function runtime must be one of: node, dotnet, python, java, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Azure Function App"
  type        = string
  default     = "20"
  
  validation {
    condition = var.function_app_runtime == "node" ? contains(["18", "20"], var.function_app_runtime_version) : (
      var.function_app_runtime == "dotnet" ? contains(["6.0", "7.0", "8.0"], var.function_app_runtime_version) : (
        var.function_app_runtime == "python" ? contains(["3.9", "3.10", "3.11"], var.function_app_runtime_version) : (
          var.function_app_runtime == "java" ? contains(["8", "11", "17"], var.function_app_runtime_version) : (
            var.function_app_runtime == "powershell" ? contains(["7.2"], var.function_app_runtime_version) : true
          )
        )
      )
    )
    error_message = "Runtime version must be compatible with the selected runtime."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan (use Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_service_plan_sku)
    error_message = "SKU must be one of: Y1 (Consumption), EP1-EP3 (Premium), P1v2-P3v2 (Dedicated)."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
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

variable "event_grid_input_schema" {
  description = "Input schema for the Event Grid topic"
  type        = string
  default     = "CloudEventSchemaV1_0"
  
  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], var.event_grid_input_schema)
    error_message = "Input schema must be one of: EventGridSchema, CloudEventSchemaV1_0, CustomInputSchema."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Retention period must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730 days."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    purpose     = "recipe-demo"
    environment = "demo"
    managed_by  = "terraform"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_function_app" {
  description = "Enable the Azure Function App deployment"
  type        = bool
  default     = true
}

variable "function_timeout_duration" {
  description = "Timeout duration for function execution (in format like 00:05:00 for 5 minutes)"
  type        = string
  default     = "00:05:00"
  
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$", var.function_timeout_duration))
    error_message = "Timeout duration must be in HH:MM:SS format, max 10 minutes for Consumption plan."
  }
}