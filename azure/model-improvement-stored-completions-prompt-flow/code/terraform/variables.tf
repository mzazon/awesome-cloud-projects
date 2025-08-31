# Variables for Model Improvement Pipeline with Stored Completions and Prompt Flow
# This file defines all configurable parameters for the Terraform deployment

#------------------------------------------------------------------------------
# GENERAL CONFIGURATION
#------------------------------------------------------------------------------

variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "South India", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports Azure OpenAI Service and ML workspace."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness and organization"
  type        = string
  default     = "mlpipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.resource_prefix))
    error_message = "Resource prefix must be 2-10 characters long and contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod) for resource tagging and configuration"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    Project   = "ModelImprovementPipeline"
    Owner     = "DataScience"
    Component = "AI-Infrastructure"
  }
}

#------------------------------------------------------------------------------
# AZURE OPENAI SERVICE CONFIGURATION
#------------------------------------------------------------------------------

variable "openai_sku" {
  description = "SKU for Azure OpenAI Service (S0 for standard workloads)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "OpenAI SKU must be S0 (only supported SKU for Azure OpenAI Service)."
  }
}

variable "openai_public_network_access_enabled" {
  description = "Enable public network access to Azure OpenAI Service (disable for enhanced security)"
  type        = bool
  default     = true
}

variable "openai_allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access Azure OpenAI Service (when public access is restricted)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.openai_allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., '192.168.1.0/24')."
  }
}

variable "openai_restrict_outbound_network_access" {
  description = "Restrict outbound network access from Azure OpenAI Service for enhanced security"
  type        = bool
  default     = false
}

variable "openai_api_version" {
  description = "Azure OpenAI API version for stored completions support"
  type        = string
  default     = "2025-02-01-preview"
  
  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}(-preview)?$", var.openai_api_version))
    error_message = "API version must be in format YYYY-MM-DD or YYYY-MM-DD-preview."
  }
}

#------------------------------------------------------------------------------
# GPT MODEL DEPLOYMENT CONFIGURATION
#------------------------------------------------------------------------------

variable "gpt4o_model_version" {
  description = "Version of GPT-4o model to deploy for conversation capture"
  type        = string
  default     = "2024-08-06"
  
  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.gpt4o_model_version))
    error_message = "Model version must be in format YYYY-MM-DD."
  }
}

variable "gpt4o_capacity" {
  description = "Capacity (tokens per minute) for GPT-4o deployment (10-1000 TPM)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt4o_capacity >= 10 && var.gpt4o_capacity <= 1000
    error_message = "GPT-4o capacity must be between 10 and 1000 tokens per minute."
  }
}

variable "model_version_upgrade_option" {
  description = "Automatic model version upgrade policy (OnceNewDefaultVersionAvailable, OnceCurrentVersionExpired, NoAutoUpgrade)"
  type        = string
  default     = "OnceNewDefaultVersionAvailable"
  
  validation {
    condition = contains([
      "OnceNewDefaultVersionAvailable",
      "OnceCurrentVersionExpired", 
      "NoAutoUpgrade"
    ], var.model_version_upgrade_option)
    error_message = "Version upgrade option must be OnceNewDefaultVersionAvailable, OnceCurrentVersionExpired, or NoAutoUpgrade."
  }
}

#------------------------------------------------------------------------------
# MACHINE LEARNING WORKSPACE CONFIGURATION
#------------------------------------------------------------------------------

variable "ml_workspace_public_access_enabled" {
  description = "Enable public network access to ML workspace (disable for enhanced security)"
  type        = bool
  default     = true
}

variable "ml_workspace_high_business_impact" {
  description = "Enable high business impact mode for enhanced security and compliance"
  type        = bool
  default     = false
}

variable "application_insights_retention_days" {
  description = "Data retention period for Application Insights (30-730 days)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

variable "container_registry_sku" {
  description = "SKU for Azure Container Registry (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_public_access_enabled" {
  description = "Enable public network access to Container Registry"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# STORAGE CONFIGURATION
#------------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_delete_retention_days" {
  description = "Number of days to retain deleted blobs and containers (1-365 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.storage_delete_retention_days >= 1 && var.storage_delete_retention_days <= 365
    error_message = "Storage delete retention must be between 1 and 365 days."
  }
}

#------------------------------------------------------------------------------
# LOG ANALYTICS AND MONITORING CONFIGURATION
#------------------------------------------------------------------------------

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace (PerGB2018, CapacityReservation, Standalone, PerNode)"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "CapacityReservation", "Standalone", "PerNode"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be PerGB2018, CapacityReservation, Standalone, or PerNode."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics workspace (30-730 days)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily data ingestion quota for Log Analytics workspace in GB (-1 for unlimited)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.log_analytics_daily_quota_gb == -1 || var.log_analytics_daily_quota_gb >= 1
    error_message = "Daily quota must be -1 (unlimited) or >= 1 GB."
  }
}

#------------------------------------------------------------------------------
# FUNCTION APP CONFIGURATION
#------------------------------------------------------------------------------

variable "function_app_sku_name" {
  description = "SKU for Function App service plan (Y1 for consumption, EP1/EP2/EP3 for premium)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_sku_name)
    error_message = "Function App SKU must be Y1 (consumption), EP1/EP2/EP3 (premium), or P1v2/P2v2/P3v2 (dedicated)."
  }
}

variable "function_app_python_version" {
  description = "Python version for Function App runtime (3.8, 3.9, 3.10, 3.11)"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_python_version)
    error_message = "Python version must be 3.8, 3.9, 3.10, or 3.11."
  }
}

variable "function_app_allowed_origins" {
  description = "List of allowed origins for CORS configuration (use ['*'] for all origins)"
  type        = list(string)
  default     = ["*"]
}

variable "function_app_scale_limit" {
  description = "Maximum number of function app instances (consumption plan: 200, premium: 100)"
  type        = number
  default     = 200
  
  validation {
    condition     = var.function_app_scale_limit >= 1 && var.function_app_scale_limit <= 200
    error_message = "Scale limit must be between 1 and 200 instances."
  }
}

variable "function_app_min_instances" {
  description = "Minimum number of pre-warmed instances (premium plans only, 0-20)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_app_min_instances >= 0 && var.function_app_min_instances <= 20
    error_message = "Minimum instances must be between 0 and 20."
  }
}

variable "function_app_prewarmed_instances" {
  description = "Number of pre-warmed instances to maintain (premium plans only, 0-20)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.function_app_prewarmed_instances >= 0 && var.function_app_prewarmed_instances <= 20
    error_message = "Pre-warmed instances must be between 0 and 20."
  }
}

#------------------------------------------------------------------------------
# PIPELINE CONFIGURATION
#------------------------------------------------------------------------------

variable "pipeline_analysis_frequency" {
  description = "Frequency for automated pipeline analysis (hourly, daily, weekly)"
  type        = string
  default     = "hourly"
  
  validation {
    condition     = contains(["hourly", "daily", "weekly"], var.pipeline_analysis_frequency)
    error_message = "Analysis frequency must be hourly, daily, or weekly."
  }
}

variable "pipeline_batch_size" {
  description = "Number of conversations to analyze in each batch (10-100)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.pipeline_batch_size >= 10 && var.pipeline_batch_size <= 100
    error_message = "Batch size must be between 10 and 100 conversations."
  }
}

variable "pipeline_quality_threshold" {
  description = "Quality threshold for conversation analysis (1.0-10.0)"
  type        = number
  default     = 7.0
  
  validation {
    condition     = var.pipeline_quality_threshold >= 1.0 && var.pipeline_quality_threshold <= 10.0
    error_message = "Quality threshold must be between 1.0 and 10.0."
  }
}

variable "pipeline_alert_quality_threshold" {
  description = "Average quality threshold that triggers alerts (1.0-10.0)"
  type        = number
  default     = 6.0
  
  validation {
    condition     = var.pipeline_alert_quality_threshold >= 1.0 && var.pipeline_alert_quality_threshold <= 10.0
    error_message = "Alert quality threshold must be between 1.0 and 10.0."
  }
}

#------------------------------------------------------------------------------
# COST OPTIMIZATION VARIABLES
#------------------------------------------------------------------------------

variable "enable_cost_optimization" {
  description = "Enable cost optimization features (reduced SKUs, shorter retention periods)"
  type        = bool
  default     = false
}

variable "auto_shutdown_enabled" {
  description = "Enable automatic shutdown of non-production resources during off-hours"
  type        = bool
  default     = false
}