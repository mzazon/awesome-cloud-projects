# Variables for Azure AI Foundry and Compute Fleet ML Scaling Infrastructure
# These variables allow customization of the deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-ml-adaptive-scaling"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US 2", "West US 3", "Central US",
      "North Europe", "West Europe", "UK South", "Southeast Asia",
      "Australia East", "Japan East", "Canada Central"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI Foundry services."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "ml-scaling"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ai_foundry_hub_name" {
  description = "Name of the AI Foundry hub workspace"
  type        = string
  default     = ""
}

variable "ai_foundry_project_name" {
  description = "Name of the AI Foundry project workspace"
  type        = string
  default     = ""
}

variable "machine_learning_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account (must be globally unique)"
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
  default     = ""
}

variable "application_insights_name" {
  description = "Name of the Application Insights resource"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "container_registry_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = ""
}

variable "compute_fleet_name" {
  description = "Name of the Azure Compute Fleet"
  type        = string
  default     = ""
}

# Compute Fleet Configuration
variable "fleet_vm_sizes" {
  description = "List of VM sizes for the compute fleet with priority ranking"
  type = list(object({
    name = string
    rank = number
  }))
  default = [
    {
      name = "Standard_D4s_v3"
      rank = 1
    },
    {
      name = "Standard_D8s_v3"
      rank = 2
    },
    {
      name = "Standard_E4s_v3"
      rank = 3
    }
  ]
}

variable "spot_instance_config" {
  description = "Configuration for spot instances in the compute fleet"
  type = object({
    capacity          = number
    min_capacity      = number
    max_price_per_vm  = number
    eviction_policy   = string
    allocation_strategy = string
  })
  default = {
    capacity          = 20
    min_capacity      = 5
    max_price_per_vm  = 0.10
    eviction_policy   = "Deallocate"
    allocation_strategy = "PriceCapacityOptimized"
  }
}

variable "regular_instance_config" {
  description = "Configuration for regular instances in the compute fleet"
  type = object({
    capacity            = number
    min_capacity        = number
    allocation_strategy = string
  })
  default = {
    capacity            = 10
    min_capacity        = 2
    allocation_strategy = "LowestPrice"
  }
}

# AI Model Configuration
variable "agent_model_configuration" {
  description = "Configuration for AI agents"
  type = object({
    model_type    = string
    model_version = string
    temperature   = number
    max_tokens    = number
  })
  default = {
    model_type    = "gpt-4"
    model_version = "2024-02-01"
    temperature   = 0.3
    max_tokens    = 2000
  }
}

# Scaling Configuration
variable "scaling_configuration" {
  description = "Configuration for ML workload scaling"
  type = object({
    scale_up_threshold   = number
    scale_down_threshold = number
    cooldown_period      = number
    max_cost_per_hour    = number
    spot_instance_ratio  = number
  })
  default = {
    scale_up_threshold   = 0.75
    scale_down_threshold = 0.25
    cooldown_period      = 300
    max_cost_per_hour    = 100
    spot_instance_ratio  = 0.7
  }
}

# Monitoring Configuration
variable "monitoring_configuration" {
  description = "Configuration for monitoring and alerting"
  type = object({
    metrics_retention_days = number
    alert_evaluation_frequency = string
    alert_window_size = string
  })
  default = {
    metrics_retention_days = 30
    alert_evaluation_frequency = "PT1M"
    alert_window_size = "PT5M"
  }
}

# Network Configuration
variable "network_configuration" {
  description = "Network configuration for the deployment"
  type = object({
    enable_private_endpoints = bool
    allowed_ip_ranges       = list(string)
  })
  default = {
    enable_private_endpoints = false
    allowed_ip_ranges       = []
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "ML-Adaptive-Scaling"
    Environment = "Demo"
    Project     = "AI-Foundry-Scaling"
    ManagedBy   = "Terraform"
  }
}