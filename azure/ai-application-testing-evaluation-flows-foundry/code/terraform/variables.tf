# Variables for Azure AI Application Testing Infrastructure
# These variables allow customization of the deployment for different environments

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI services."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ai-testing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ai_services_sku" {
  description = "SKU for Azure AI Services (Cognitive Services)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3"], var.ai_services_sku)
    error_message = "AI Services SKU must be one of: F0, S0, S1, S2, S3."
  }
}

variable "openai_model_name" {
  description = "OpenAI model name for evaluation"
  type        = string
  default     = "gpt-4o-mini"
  
  validation {
    condition     = contains(["gpt-4o-mini", "gpt-4o", "gpt-35-turbo", "gpt-4"], var.openai_model_name)
    error_message = "OpenAI model must be one of the supported models for evaluation."
  }
}

variable "openai_model_version" {
  description = "OpenAI model version"
  type        = string
  default     = "2024-07-18"
}

variable "openai_deployment_capacity" {
  description = "Capacity for OpenAI model deployment (in thousands of tokens per minute)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 1000
    error_message = "OpenAI deployment capacity must be between 1 and 1000."
  }
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
    condition     = contains(["LRS", "GRS", "ZRS", "GZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, ZRS, GZRS."
  }
}

variable "enable_public_network_access" {
  description = "Enable public network access to AI services"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    "Project"     = "AI-Testing"
    "Environment" = "Demo"
    "Purpose"     = "GenAI-Evaluation"
  }
}

variable "create_devops_service_connection" {
  description = "Create placeholder outputs for Azure DevOps service connection"
  type        = bool
  default     = true
}

# Local variables for computed values
locals {
  # Generate unique suffix for resource naming
  unique_suffix = random_string.suffix.result
  
  # Auto-generate resource group name if not provided
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.unique_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    "Environment"   = var.environment
    "Project"       = var.project_name
    "DeployedBy"    = "Terraform"
    "CreatedDate"   = timestamp()
  })
  
  # Naming convention for resources
  naming_prefix = "${var.project_name}-${var.environment}"
  
  # AI Services and Storage account names (must be globally unique)
  ai_services_name   = "ai-${substr(lower(replace("${local.naming_prefix}-${local.unique_suffix}", "-", "")), 0, 24)}"
  storage_account_name = "st${substr(lower(replace("${local.naming_prefix}${local.unique_suffix}", "-", "")), 0, 22)}"
  
  # OpenAI deployment name
  openai_deployment_name = "${var.openai_model_name}-eval"
}