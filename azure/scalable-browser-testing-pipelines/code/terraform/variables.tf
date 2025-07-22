# Variables for Azure Playwright Testing with Azure DevOps Infrastructure
# This file defines all configurable parameters for the deployment

# Core configuration variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 3", "East Asia", "West Europe"
    ], var.location)
    error_message = "Azure Playwright Testing is currently available in East US, West US 3, East Asia, and West Europe regions only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-playwright-testing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name can only contain letters, numbers, periods, hyphens, and underscores."
  }
}

variable "project_name" {
  description = "Name of the project - used as prefix for resource names"
  type        = string
  default     = "playwright-testing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name can only contain letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Azure Playwright Testing configuration
variable "playwright_workspace_name" {
  description = "Name of the Azure Playwright Testing workspace"
  type        = string
  default     = ""
  
  validation {
    condition     = var.playwright_workspace_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.playwright_workspace_name))
    error_message = "Playwright workspace name can only contain letters, numbers, and hyphens."
  }
}

variable "playwright_workspace_sku" {
  description = "SKU for the Azure Playwright Testing workspace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.playwright_workspace_sku)
    error_message = "Playwright workspace SKU must be one of: Free, Standard, Premium."
  }
}

# Azure Container Registry configuration
variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = ""
  
  validation {
    condition     = var.acr_name == "" || can(regex("^[a-zA-Z0-9]+$", var.acr_name))
    error_message = "ACR name can only contain alphanumeric characters."
  }
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

variable "acr_admin_enabled" {
  description = "Enable admin user for Azure Container Registry"
  type        = bool
  default     = true
}

# Azure DevOps configuration
variable "azuredevops_project_name" {
  description = "Name of the Azure DevOps project"
  type        = string
  default     = "playwright-testing-project"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._-]+$", var.azuredevops_project_name))
    error_message = "Azure DevOps project name can contain letters, numbers, spaces, periods, hyphens, and underscores."
  }
}

variable "azuredevops_project_description" {
  description = "Description for the Azure DevOps project"
  type        = string
  default     = "Automated browser testing with Azure Playwright Testing"
}

variable "azuredevops_project_visibility" {
  description = "Visibility of the Azure DevOps project"
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "public"], var.azuredevops_project_visibility)
    error_message = "Azure DevOps project visibility must be either 'private' or 'public'."
  }
}

variable "azuredevops_project_version_control" {
  description = "Version control system for the Azure DevOps project"
  type        = string
  default     = "Git"
  
  validation {
    condition     = contains(["Git", "Tfvc"], var.azuredevops_project_version_control)
    error_message = "Version control must be either 'Git' or 'Tfvc'."
  }
}

variable "azuredevops_project_work_item_template" {
  description = "Work item template for the Azure DevOps project"
  type        = string
  default     = "Agile"
  
  validation {
    condition     = contains(["Agile", "Basic", "Scrum", "CMMI"], var.azuredevops_project_work_item_template)
    error_message = "Work item template must be one of: Agile, Basic, Scrum, CMMI."
  }
}

# Pipeline configuration
variable "pipeline_name" {
  description = "Name of the Azure DevOps pipeline"
  type        = string
  default     = "Playwright-Testing-Pipeline"
}

variable "pipeline_yaml_path" {
  description = "Path to the pipeline YAML file in the repository"
  type        = string
  default     = ".azure-pipelines/playwright-pipeline.yml"
}

variable "pipeline_branch" {
  description = "Default branch for the pipeline"
  type        = string
  default     = "main"
}

# Key Vault configuration (for storing sensitive pipeline variables)
variable "key_vault_name" {
  description = "Name of the Azure Key Vault for storing pipeline secrets"
  type        = string
  default     = ""
  
  validation {
    condition     = var.key_vault_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.key_vault_name))
    error_message = "Key Vault name can only contain letters, numbers, and hyphens."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for pipeline notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

# Tagging configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Playwright Testing"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "Browser Testing"
  }
}

# Advanced configuration
variable "enable_monitoring" {
  description = "Enable monitoring and logging for resources"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for applicable resources"
  type        = bool
  default     = true
}

variable "delete_protection" {
  description = "Enable delete protection for critical resources"
  type        = bool
  default     = true
}

variable "node_version" {
  description = "Node.js version for pipeline"
  type        = string
  default     = "18.x"
  
  validation {
    condition     = can(regex("^[0-9]+\\.x$", var.node_version))
    error_message = "Node version must be in format 'XX.x' (e.g., '18.x')."
  }
}

variable "playwright_browsers" {
  description = "List of browsers to test with Playwright"
  type        = list(string)
  default     = ["chromium", "firefox", "webkit"]
  
  validation {
    condition = alltrue([
      for browser in var.playwright_browsers : contains(["chromium", "firefox", "webkit"], browser)
    ])
    error_message = "Supported browsers are: chromium, firefox, webkit."
  }
}