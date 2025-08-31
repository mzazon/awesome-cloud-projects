# Variables for Azure Intelligent Product Catalog Infrastructure
# These variables allow customization of the deployment

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "catalog"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
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

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports OpenAI services."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (if empty, will be generated)"
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

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Storage account access tier"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "function_app_runtime" {
  description = "Function App runtime stack"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Function App runtime version"
  type        = string
  default     = "3.11"
  
  validation {
    condition = var.function_app_runtime == "python" ? contains(["3.8", "3.9", "3.10", "3.11"]) : true
    error_message = "For Python runtime, version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

variable "openai_sku_name" {
  description = "Azure OpenAI Service SKU"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be S0 for standard pricing tier."
  }
}

variable "openai_model_name" {
  description = "OpenAI model to deploy"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-35-turbo"], var.openai_model_name)
    error_message = "OpenAI model must be one of: gpt-4o, gpt-4, gpt-35-turbo."
  }
}

variable "openai_model_version" {
  description = "OpenAI model version"
  type        = string
  default     = "2024-11-20"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.openai_model_version))
    error_message = "OpenAI model version must be in YYYY-MM-DD format."
  }
}

variable "openai_deployment_capacity" {
  description = "OpenAI deployment capacity (TPM - Tokens Per Minute)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 300
    error_message = "OpenAI deployment capacity must be between 1 and 300 TPM."
  }
}

variable "function_app_plan_sku" {
  description = "Function App Service Plan SKU"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function App Plan SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_storage_logging" {
  description = "Enable storage account logging"
  type        = bool
  default     = true
}

variable "blob_containers" {
  description = "List of blob containers to create"
  type = list(object({
    name        = string
    access_type = string
  }))
  default = [
    {
      name        = "product-images"
      access_type = "private"
    },
    {
      name        = "catalog-results"
      access_type = "private"
    }
  ]
  
  validation {
    condition = alltrue([
      for container in var.blob_containers : contains(["private", "blob", "container"], container.access_type)
    ])
    error_message = "Container access type must be one of: private, blob, container."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    Project     = "intelligent-product-catalog"
    ManagedBy   = "terraform"
  }
}

variable "openai_content_filter_config" {
  description = "Content filter configuration for OpenAI"
  type = object({
    hate_threshold     = string
    sexual_threshold   = string
    violence_threshold = string
    self_harm_threshold = string
  })
  default = {
    hate_threshold     = "medium"
    sexual_threshold   = "medium"
    violence_threshold = "medium"
    self_harm_threshold = "medium"
  }
  
  validation {
    condition = alltrue([
      contains(["low", "medium", "high"], var.openai_content_filter_config.hate_threshold),
      contains(["low", "medium", "high"], var.openai_content_filter_config.sexual_threshold),
      contains(["low", "medium", "high"], var.openai_content_filter_config.violence_threshold),
      contains(["low", "medium", "high"], var.openai_content_filter_config.self_harm_threshold)
    ])
    error_message = "All content filter thresholds must be one of: low, medium, high."
  }
}

variable "function_timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 30 && var.function_timeout <= 600
    error_message = "Function timeout must be between 30 and 600 seconds."
  }
}

variable "storage_cors_rules" {
  description = "CORS rules for storage account"
  type = list(object({
    allowed_headers    = list(string)
    allowed_methods    = list(string)
    allowed_origins    = list(string)
    exposed_headers    = list(string)
    max_age_in_seconds = number
  }))
  default = [
    {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  ]
}