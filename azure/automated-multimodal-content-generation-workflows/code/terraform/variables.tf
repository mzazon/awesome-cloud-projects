# Variables for Azure Multi-Modal Content Generation Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-multimodal-content"
  
  validation {
    condition     = length(var.resource_group_name) > 0 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "multimodal-content"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "Project name must be 3-24 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ai_foundry_hub_name" {
  description = "Name for the Azure AI Foundry Hub"
  type        = string
  default     = ""
}

variable "ai_foundry_project_name" {
  description = "Name for the Azure AI Foundry Project"
  type        = string
  default     = ""
}

variable "container_registry_name" {
  description = "Name for the Azure Container Registry"
  type        = string
  default     = ""
  
  validation {
    condition     = var.container_registry_name == "" || can(regex("^[a-zA-Z0-9]{5,50}$", var.container_registry_name))
    error_message = "Container registry name must be 5-50 characters long and contain only alphanumeric characters."
  }
}

variable "storage_account_name" {
  description = "Name for the storage account"
  type        = string
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "key_vault_name" {
  description = "Name for the Key Vault"
  type        = string
  default     = ""
  
  validation {
    condition     = var.key_vault_name == "" || can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "event_grid_topic_name" {
  description = "Name for the Event Grid Topic"
  type        = string
  default     = ""
}

variable "function_app_name" {
  description = "Name for the Function App"
  type        = string
  default     = ""
}

variable "container_registry_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App Service Plan SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Premium)."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights and monitoring"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for resource access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "Purpose"     = "Multi-Modal Content Generation"
    "Environment" = "Demo"
    "CreatedBy"   = "Terraform"
    "Recipe"      = "azure-multimodal-content-generation"
  }
}

variable "ai_models_to_deploy" {
  description = "List of AI models to deploy in Azure AI Foundry"
  type = list(object({
    name               = string
    model_id          = string
    instance_type     = string
    instance_count    = number
    deployment_name   = string
  }))
  default = [
    {
      name               = "gpt-4o"
      model_id          = "azureml://registries/azureml/models/gpt-4o/versions/2024-08-06"
      instance_type     = "Standard_NC6s_v3"
      instance_count    = 1
      deployment_name   = "gpt4o-text-deployment"
    },
    {
      name               = "dall-e-3"
      model_id          = "azureml://registries/azureml/models/dall-e-3/versions/latest"
      instance_type     = "Standard_NC12s_v3"
      instance_count    = 1
      deployment_name   = "dalle3-image-deployment"
    }
  ]
}

variable "content_coordination_config" {
  description = "Configuration for multi-modal content coordination"
  type = object({
    workflows = map(object({
      text_model  = string
      image_model = string
      audio_model = optional(string)
      coordination_rules = object({
        style_consistency = bool
        brand_alignment   = bool
        message_coherence = bool
      })
    }))
    quality_gates = object({
      content_safety      = bool
      brand_compliance    = bool
      technical_validation = bool
    })
  })
  default = {
    workflows = {
      marketing_campaign = {
        text_model  = "gpt-4o"
        image_model = "dall-e-3"
        audio_model = "speech-synthesis"
        coordination_rules = {
          style_consistency = true
          brand_alignment   = true
          message_coherence = true
        }
      }
      social_media = {
        text_model  = "gpt-4o-mini"
        image_model = "dall-e-3"
        coordination_rules = {
          style_consistency = true
          brand_alignment   = true
          message_coherence = true
        }
      }
    }
    quality_gates = {
      content_safety       = true
      brand_compliance     = true
      technical_validation = true
    }
  }
}