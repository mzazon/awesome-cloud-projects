# Variable definitions for Azure AI Studio Prompt Flow and Container Apps infrastructure
# These variables allow customization of the deployment while maintaining best practices

# General Configuration Variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West", "Korea Central",
      "South India", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI services and Container Apps."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "ai-promptflow"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group to create. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

# Azure AI Studio Configuration
variable "ai_hub_name" {
  description = "Name of the Azure AI Hub. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "ai_project_name" {
  description = "Name of the Azure AI Project. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "ai_hub_sku" {
  description = "SKU for the Azure AI Hub workspace"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.ai_hub_sku)
    error_message = "AI Hub SKU must be Basic, Standard, or Premium."
  }
}

# Azure OpenAI Configuration
variable "openai_account_name" {
  description = "Name of the Azure OpenAI account. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "openai_sku" {
  description = "SKU for the Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku)
    error_message = "OpenAI SKU must be F0 (free tier) or S0 (standard)."
  }
}

variable "openai_model_name" {
  description = "Name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-35-turbo"
  
  validation {
    condition = contains([
      "gpt-35-turbo", "gpt-35-turbo-16k", "gpt-4", "gpt-4-32k",
      "text-embedding-ada-002", "text-davinci-003", "code-davinci-002"
    ], var.openai_model_name)
    error_message = "OpenAI model must be a supported model name."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "0613"
}

variable "openai_model_capacity" {
  description = "Capacity (TPM - Tokens Per Minute) for the OpenAI model deployment"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_model_capacity >= 1 && var.openai_model_capacity <= 1000
    error_message = "OpenAI model capacity must be between 1 and 1000 TPM."
  }
}

# Container Registry Configuration
variable "container_registry_name" {
  description = "Name of the Azure Container Registry. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "container_registry_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for the Container Registry"
  type        = bool
  default     = true
}

# Container Apps Configuration
variable "container_app_env_name" {
  description = "Name of the Container Apps environment. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "container_app_name" {
  description = "Name of the Container App. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "container_app_cpu" {
  description = "CPU allocation for the container app"
  type        = number
  default     = 0.25
  
  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], var.container_app_cpu)
    error_message = "Container App CPU must be one of: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0."
  }
}

variable "container_app_memory" {
  description = "Memory allocation for the container app (in Gi)"
  type        = string
  default     = "0.5Gi"
  
  validation {
    condition = contains([
      "0.5Gi", "1Gi", "1.5Gi", "2Gi", "2.5Gi", "3Gi", "3.5Gi", "4Gi"
    ], var.container_app_memory)
    error_message = "Container App memory must be one of: 0.5Gi, 1Gi, 1.5Gi, 2Gi, 2.5Gi, 3Gi, 3.5Gi, 4Gi."
  }
}

variable "container_app_min_replicas" {
  description = "Minimum number of replicas for the container app (set to 0 for scale-to-zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.container_app_min_replicas >= 0 && var.container_app_min_replicas <= 25
    error_message = "Minimum replicas must be between 0 and 25."
  }
}

variable "container_app_max_replicas" {
  description = "Maximum number of replicas for the container app"
  type        = number
  default     = 10
  
  validation {
    condition     = var.container_app_max_replicas >= 1 && var.container_app_max_replicas <= 25
    error_message = "Maximum replicas must be between 1 and 25."
  }
}

variable "container_app_target_port" {
  description = "Target port for the container app"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.container_app_target_port >= 1 && var.container_app_target_port <= 65535
    error_message = "Target port must be between 1 and 65535."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier for AI Hub storage"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, Standalone, PerNode, or PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance. If empty, will be generated based on project_name and environment"
  type        = string
  default     = ""
}

# Tagging Configuration
variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    "Project"     = "AI Prompt Flow"
    "Environment" = "Development"
    "ManagedBy"   = "Terraform"
    "Purpose"     = "Serverless AI Workflows"
  }
}

# Feature Flags
variable "enable_monitoring" {
  description = "Enable Application Insights and monitoring features"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoints for supported services (requires Standard/Premium SKUs)"
  type        = bool
  default     = false
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for Container App"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration (empty list allows all origins)"
  type        = list(string)
  default     = []
}

variable "network_access_tier" {
  description = "Network access configuration for AI services (Public, Private, or Hybrid)"
  type        = string
  default     = "Public"
  
  validation {
    condition     = contains(["Public", "Private", "Hybrid"], var.network_access_tier)
    error_message = "Network access tier must be Public, Private, or Hybrid."
  }
}