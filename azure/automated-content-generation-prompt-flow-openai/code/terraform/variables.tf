# ==============================================================================
# VARIABLES DEFINITION
# Azure Automated Content Generation with Prompt Flow and OpenAI
# ==============================================================================

# Required Variables
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East", "Switzerland North",
      "UAE North", "South Africa North",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Korea South",
      "Southeast Asia", "East Asia",
      "Central India", "South India", "West India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "openai_location" {
  description = "The Azure region for OpenAI service deployment (limited availability)"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2",
      "Canada East", "Canada Central",
      "UK South", "West Europe", "France Central",
      "Switzerland North", "Sweden Central",
      "Australia East", "Japan East"
    ], var.openai_location)
    error_message = "The OpenAI location must be a region where Azure OpenAI is available."
  }
}

# Resource Naming Variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "rg"

  validation {
    condition     = length(var.resource_prefix) >= 2 && length(var.resource_prefix) <= 10
    error_message = "Resource prefix must be between 2 and 10 characters."
  }
}

variable "storage_prefix" {
  description = "Prefix for storage account names (must be lowercase, no special characters)"
  type        = string
  default     = "stor"

  validation {
    condition     = length(var.storage_prefix) >= 3 && length(var.storage_prefix) <= 10 && can(regex("^[a-z0-9]+$", var.storage_prefix))
    error_message = "Storage prefix must be 3-10 characters, lowercase letters and numbers only."
  }
}

# Azure OpenAI Model Configuration
variable "gpt4o_capacity" {
  description = "The capacity (TPM in thousands) for GPT-4o model deployment"
  type        = number
  default     = 10

  validation {
    condition     = var.gpt4o_capacity >= 1 && var.gpt4o_capacity <= 100
    error_message = "GPT-4o capacity must be between 1 and 100 TPM (thousands)."
  }
}

variable "embedding_capacity" {
  description = "The capacity (TPM in thousands) for text embedding model deployment"
  type        = number
  default     = 10

  validation {
    condition     = var.embedding_capacity >= 1 && var.embedding_capacity <= 100
    error_message = "Embedding capacity must be between 1 and 100 TPM (thousands)."
  }
}

# Function App Configuration
variable "function_app_sku" {
  description = "The SKU for the Function App service plan"
  type        = string
  default     = "Y1" # Consumption plan for serverless scaling

  validation {
    condition = contains([
      "Y1",           # Consumption plan
      "EP1", "EP2", "EP3", # Elastic Premium plans
      "P1v2", "P2v2", "P3v2" # Premium v2 plans
    ], var.function_app_sku)
    error_message = "Function App SKU must be a valid App Service plan SKU."
  }
}

# Cosmos DB Configuration
variable "cosmos_throughput" {
  description = "The throughput (RU/s) for Cosmos DB container"
  type        = number
  default     = 400

  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 4000
    error_message = "Cosmos DB throughput must be between 400 and 4000 RU/s."
  }
}

variable "cosmos_consistency_level" {
  description = "The consistency level for Cosmos DB account"
  type        = string
  default     = "Eventual"

  validation {
    condition = contains([
      "Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"
    ], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "The tier for the storage account"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"

  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Monitoring and Logging Configuration
variable "log_analytics_retention_days" {
  description = "The retention period in days for Log Analytics workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "enable_backup" {
  description = "Enable backup for Cosmos DB"
  type        = bool
  default     = true
}

variable "backup_interval_minutes" {
  description = "The backup interval in minutes for Cosmos DB"
  type        = number
  default     = 240

  validation {
    condition     = var.backup_interval_minutes >= 60 && var.backup_interval_minutes <= 1440
    error_message = "Backup interval must be between 60 and 1440 minutes."
  }
}

variable "backup_retention_hours" {
  description = "The backup retention in hours for Cosmos DB"
  type        = number
  default     = 8

  validation {
    condition     = var.backup_retention_hours >= 8 && var.backup_retention_hours <= 720
    error_message = "Backup retention must be between 8 and 720 hours."
  }
}

# Security Configuration
variable "public_network_access_enabled" {
  description = "Enable public network access for services"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "The minimum TLS version for storage accounts"
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# Content Generation Configuration
variable "default_content_tone" {
  description = "Default tone for content generation"
  type        = string
  default     = "professional"

  validation {
    condition = contains([
      "professional", "casual", "formal", "friendly", "technical", "creative"
    ], var.default_content_tone)
    error_message = "Content tone must be one of: professional, casual, formal, friendly, technical, creative."
  }
}

variable "default_campaign_type" {
  description = "Default campaign type for content generation"
  type        = string
  default     = "social_media"

  validation {
    condition = contains([
      "social_media", "email", "blog", "advertisement", "newsletter", "press_release"
    ], var.default_campaign_type)
    error_message = "Campaign type must be one of: social_media, email, blog, advertisement, newsletter, press_release."
  }
}

variable "max_content_length" {
  description = "Maximum length for generated content (in characters)"
  type        = number
  default     = 2000

  validation {
    condition     = var.max_content_length >= 100 && var.max_content_length <= 10000
    error_message = "Maximum content length must be between 100 and 10000 characters."
  }
}

# Environment and Deployment Configuration
variable "environment" {
  description = "The deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "deployment_region" {
  description = "The deployment region identifier"
  type        = string
  default     = "primary"

  validation {
    condition     = contains(["primary", "secondary", "disaster_recovery"], var.deployment_region)
    error_message = "Deployment region must be one of: primary, secondary, disaster_recovery."
  }
}

# Cost Management Configuration
variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 100

  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

# Advanced Configuration
variable "enable_advanced_security" {
  description = "Enable advanced security features (may incur additional costs)"
  type        = bool
  default     = false
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for all services"
  type        = bool
  default     = true
}

# Tagging Strategy
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project      = "Content Generation"
    Environment  = "Development"
    ManagedBy    = "Terraform"
    Purpose      = "AI Content Generation"
    CostCenter   = "Marketing"
    Owner        = "AI Team"
    CreatedDate  = ""
  }

  validation {
    condition     = length(var.common_tags) <= 50
    error_message = "Maximum of 50 tags allowed per resource."
  }
}

# Network Configuration (for future private endpoint support)
variable "virtual_network_address_space" {
  description = "Address space for virtual network (used when private endpoints are enabled)"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "At least one address space must be specified for virtual network."
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets (used when private endpoints are enabled)"
  type        = map(string)
  default = {
    "functions"    = "10.0.1.0/24"
    "ml_workspace" = "10.0.2.0/24"
    "storage"      = "10.0.3.0/24"
    "cosmos"       = "10.0.4.0/24"
    "openai"       = "10.0.5.0/24"
  }
}