# Core Configuration Variables
variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = "rg-intelligent-pipeline"
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "UK South", "UK West", "West Europe", "North Europe",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Central India", "South India", "West India", "UAE North",
      "South Africa North", "Brazil South"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment name must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "intelligent-pipeline"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Azure AI Foundry Configuration
variable "ai_foundry_hub_name" {
  description = "Name of the Azure AI Foundry Hub"
  type        = string
  default     = ""
}

variable "ai_foundry_project_name" {
  description = "Name of the Azure AI Foundry Project"
  type        = string
  default     = ""
}

variable "ai_foundry_sku" {
  description = "SKU for Azure AI Foundry services"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.ai_foundry_sku)
    error_message = "AI Foundry SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

# Azure Data Factory Configuration
variable "data_factory_name" {
  description = "Name of the Azure Data Factory instance"
  type        = string
  default     = ""
}

variable "data_factory_managed_identity" {
  description = "Enable managed identity for Azure Data Factory"
  type        = bool
  default     = true
}

variable "data_factory_public_network_enabled" {
  description = "Enable public network access for Data Factory"
  type        = bool
  default     = true
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Storage account tier"
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

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Azure Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Log Analytics Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Log Analytics data retention in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_in_days >= 7 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

# Event Grid Configuration
variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = ""
}

variable "event_grid_input_schema" {
  description = "Event Grid input schema"
  type        = string
  default     = "EventGridSchema"
  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], var.event_grid_input_schema)
    error_message = "Event Grid input schema must be one of: EventGridSchema, CloudEventSchemaV1_0, CustomInputSchema."
  }
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = ""
}

variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Key Vault soft delete retention period in days"
  type        = number
  default     = 7
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Cognitive Services Configuration
variable "cognitive_services_name" {
  description = "Name of the Cognitive Services account"
  type        = string
  default     = ""
}

variable "cognitive_services_sku" {
  description = "Cognitive Services SKU"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

# Agent Configuration
variable "agent_configurations" {
  description = "Configuration for AI agents"
  type = map(object({
    name           = string
    description    = string
    model_type     = string
    temperature    = number
    max_tokens     = number
    schedule       = string
    priority       = number
    capabilities   = list(string)
  }))
  default = {
    monitoring = {
      name           = "PipelineMonitoringAgent"
      description    = "Autonomous agent for monitoring Azure Data Factory pipeline performance and health"
      model_type     = "gpt-4o"
      temperature    = 0.3
      max_tokens     = 1000
      schedule       = "0 */5 * * * *"
      priority       = 1
      capabilities   = ["monitoring", "alerting", "trend-analysis"]
    }
    quality = {
      name           = "DataQualityAnalyzerAgent"
      description    = "Intelligent agent for analyzing data quality and implementing automated quality improvements"
      model_type     = "gpt-4o"
      temperature    = 0.2
      max_tokens     = 1200
      schedule       = "0 0 */4 * * *"
      priority       = 2
      capabilities   = ["quality-analysis", "data-profiling", "quality-improvement"]
    }
    performance = {
      name           = "PerformanceOptimizationAgent"
      description    = "Autonomous agent for optimizing Azure Data Factory pipeline performance and resource utilization"
      model_type     = "gpt-4o"
      temperature    = 0.1
      max_tokens     = 1500
      schedule       = "0 0 */6 * * *"
      priority       = 2
      capabilities   = ["performance-optimization", "resource-management", "cost-optimization"]
    }
    healing = {
      name           = "SelfHealingAgent"
      description    = "Autonomous agent for implementing self-healing capabilities in Azure Data Factory pipelines"
      model_type     = "gpt-4o"
      temperature    = 0.4
      max_tokens     = 1300
      schedule       = "0 */10 * * * *"
      priority       = 3
      capabilities   = ["failure-recovery", "automated-remediation", "incident-response"]
    }
  }
}

# Monitoring Configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "diagnostic_log_categories" {
  description = "List of diagnostic log categories to enable"
  type        = list(string)
  default     = ["PipelineRuns", "ActivityRuns", "TriggerRuns", "SSISPackageExecution", "SSISIntegrationRuntimeLogs"]
}

variable "diagnostic_metric_categories" {
  description = "List of diagnostic metric categories to enable"
  type        = list(string)
  default     = ["AllMetrics"]
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "intelligent-pipeline-automation"
    ManagedBy   = "terraform"
  }
}

# Network Configuration
variable "create_private_endpoints" {
  description = "Create private endpoints for services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

# Cost Management
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "auto_shutdown_enabled" {
  description = "Enable auto-shutdown for compute resources"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Time for auto-shutdown in 24-hour format (e.g., 1800 for 6:00 PM)"
  type        = string
  default     = "1800"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto-shutdown time must be in 24-hour format (e.g., 1800 for 6:00 PM)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown"
  type        = string
  default     = "UTC"
}