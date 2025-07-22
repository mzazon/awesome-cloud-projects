# Input Variables for Azure Data Governance Solution
# This file defines all configurable parameters for the Terraform deployment

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure resource group to create or use"
  type        = string
  default     = "rg-purview-governance-demo"

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "Central India", "South India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging (dev, test, prod)"
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Naming and Tagging Variables
variable "name_prefix" {
  description = "Prefix to use for resource names to ensure uniqueness"
  type        = string
  default     = "purview"

  validation {
    condition     = length(var.name_prefix) >= 2 && length(var.name_prefix) <= 10
    error_message = "Name prefix must be between 2 and 10 characters."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "data-governance"
    Environment = "demo"
    Solution    = "purview-data-lake-governance"
  }
}

# Azure Purview Configuration
variable "purview_account_name" {
  description = "Name for the Azure Purview account (will be suffixed with random string if not globally unique)"
  type        = string
  default     = ""

  validation {
    condition     = var.purview_account_name == "" || (length(var.purview_account_name) >= 3 && length(var.purview_account_name) <= 63)
    error_message = "Purview account name must be between 3 and 63 characters when specified."
  }
}

variable "purview_managed_resource_group_name" {
  description = "Name for the Purview managed resource group (auto-generated if not specified)"
  type        = string
  default     = ""
}

variable "purview_public_network_access" {
  description = "Enable public network access for Purview account"
  type        = bool
  default     = true
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name for the Data Lake Storage account (will be suffixed with random string if not globally unique)"
  type        = string
  default     = ""

  validation {
    condition     = var.storage_account_name == "" || (length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 20)
    error_message = "Storage account name must be between 3 and 20 characters when specified."
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

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Invalid storage replication type."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning for the storage account"
  type        = bool
  default     = true
}

variable "enable_change_feed" {
  description = "Enable change feed for the storage account"
  type        = bool
  default     = true
}

# Data Lake Containers Configuration
variable "data_containers" {
  description = "Configuration for Data Lake Storage containers"
  type = map(object({
    access_type = string
    metadata    = map(string)
  }))
  default = {
    "raw-data" = {
      access_type = "private"
      metadata = {
        purpose = "raw-data-ingestion"
        tier    = "hot"
      }
    }
    "processed-data" = {
      access_type = "private"
      metadata = {
        purpose = "processed-analytics-data"
        tier    = "hot"
      }
    }
    "sensitive-data" = {
      access_type = "private"
      metadata = {
        purpose = "sensitive-pii-data"
        tier    = "hot"
        classification = "confidential"
      }
    }
  }
}

# Azure Synapse Analytics Configuration
variable "synapse_workspace_name" {
  description = "Name for the Azure Synapse Analytics workspace"
  type        = string
  default     = ""

  validation {
    condition     = var.synapse_workspace_name == "" || (length(var.synapse_workspace_name) >= 1 && length(var.synapse_workspace_name) <= 50)
    error_message = "Synapse workspace name must be between 1 and 50 characters when specified."
  }
}

variable "synapse_sql_admin_login" {
  description = "SQL administrator login for Synapse workspace"
  type        = string
  default     = "sqladminuser"

  validation {
    condition     = length(var.synapse_sql_admin_login) >= 1 && length(var.synapse_sql_admin_login) <= 128
    error_message = "SQL admin login must be between 1 and 128 characters."
  }
}

variable "synapse_sql_admin_password" {
  description = "SQL administrator password for Synapse workspace"
  type        = string
  default     = "ComplexP@ssw0rd123!"
  sensitive   = true

  validation {
    condition     = length(var.synapse_sql_admin_password) >= 8 && length(var.synapse_sql_admin_password) <= 128
    error_message = "SQL admin password must be between 8 and 128 characters."
  }
}

variable "enable_synapse_workspace" {
  description = "Enable creation of Azure Synapse Analytics workspace"
  type        = bool
  default     = true
}

# Network Security Configuration
variable "allowed_ip_addresses" {
  description = "List of IP addresses allowed to access resources"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allowed_ip_addresses : can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))
    ])
    error_message = "All IP addresses must be valid IPv4 addresses."
  }
}

variable "enable_azure_services_access" {
  description = "Allow Azure services to access the resources"
  type        = bool
  default     = true
}

# Data Classification Configuration
variable "enable_data_classification" {
  description = "Enable automatic data classification and sensitivity labeling"
  type        = bool
  default     = true
}

variable "classification_rules" {
  description = "Custom classification rules for data governance"
  type = map(object({
    description        = string
    classification     = string
    rule_type         = string
    pattern           = string
    column_names      = list(string)
    severity          = string
  }))
  default = {
    "customer-email" = {
      description    = "Identifies customer email addresses"
      classification = "Email Address"
      rule_type      = "Regex"
      pattern        = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
      column_names   = ["email", "email_address", "customer_email"]
      severity       = "High"
    }
    "customer-phone" = {
      description    = "Identifies customer phone numbers"
      classification = "Phone Number"
      rule_type      = "Regex"
      pattern        = "^\\+?[1-9]\\d{1,14}$|^\\(?\\d{3}\\)?[-\\s.]?\\d{3}[-\\s.]?\\d{4}$"
      column_names   = ["phone", "phone_number", "customer_phone"]
      severity       = "Medium"
    }
  }
}

# Monitoring and Logging Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Cost Management Configuration
variable "enable_cost_alerts" {
  description = "Enable cost management alerts for the resource group"
  type        = bool
  default     = false
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 500

  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}