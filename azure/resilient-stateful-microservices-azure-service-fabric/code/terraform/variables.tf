# Variables for Azure Stateful Microservices Orchestration Infrastructure
# This file defines configurable parameters for the Service Fabric and Durable Functions deployment

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-microservices-orchestration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
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
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "microservices-orchestration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Service Fabric Configuration Variables
variable "service_fabric_cluster_name" {
  description = "Name of the Service Fabric cluster"
  type        = string
  default     = ""
  
  validation {
    condition     = var.service_fabric_cluster_name == "" || can(regex("^[a-z0-9-]{4,23}$", var.service_fabric_cluster_name))
    error_message = "Service Fabric cluster name must be 4-23 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_fabric_node_count" {
  description = "Number of nodes in the Service Fabric cluster"
  type        = number
  default     = 3
  
  validation {
    condition     = var.service_fabric_node_count >= 3 && var.service_fabric_node_count <= 100
    error_message = "Service Fabric node count must be between 3 and 100."
  }
}

variable "service_fabric_vm_size" {
  description = "VM size for Service Fabric nodes"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_D16s_v3", "Standard_D32s_v3", "Standard_D64s_v3",
      "Standard_F2s_v2", "Standard_F4s_v2", "Standard_F8s_v2",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3"
    ], var.service_fabric_vm_size)
    error_message = "VM size must be a valid Azure VM size suitable for Service Fabric."
  }
}

variable "service_fabric_reliability_level" {
  description = "Reliability level for Service Fabric cluster"
  type        = string
  default     = "Silver"
  
  validation {
    condition     = contains(["Bronze", "Silver", "Gold", "Platinum"], var.service_fabric_reliability_level)
    error_message = "Reliability level must be Bronze, Silver, Gold, or Platinum."
  }
}

variable "service_fabric_durability_level" {
  description = "Durability level for Service Fabric cluster"
  type        = string
  default     = "Silver"
  
  validation {
    condition     = contains(["Bronze", "Silver", "Gold"], var.service_fabric_durability_level)
    error_message = "Durability level must be Bronze, Silver, or Gold."
  }
}

variable "service_fabric_upgrade_mode" {
  description = "Upgrade mode for Service Fabric cluster"
  type        = string
  default     = "Automatic"
  
  validation {
    condition     = contains(["Automatic", "Manual"], var.service_fabric_upgrade_mode)
    error_message = "Upgrade mode must be Automatic or Manual."
  }
}

variable "service_fabric_admin_username" {
  description = "Administrator username for Service Fabric VMs"
  type        = string
  default     = "sfadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,19}$", var.service_fabric_admin_username))
    error_message = "Admin username must be 3-20 characters, start with a letter, and contain only alphanumeric characters."
  }
}

variable "service_fabric_admin_password" {
  description = "Administrator password for Service Fabric VMs"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = var.service_fabric_admin_password == "" || can(regex("^.{12,123}$", var.service_fabric_admin_password))
    error_message = "Admin password must be 12-123 characters long if provided."
  }
}

# SQL Database Configuration Variables
variable "sql_server_name" {
  description = "Name of the SQL Server"
  type        = string
  default     = ""
  
  validation {
    condition     = var.sql_server_name == "" || can(regex("^[a-z0-9-]{1,63}$", var.sql_server_name))
    error_message = "SQL Server name must be 1-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "sql_database_name" {
  description = "Name of the SQL Database"
  type        = string
  default     = "MicroservicesState"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.sql_database_name))
    error_message = "SQL Database name must be 1-128 characters long and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "sql_admin_login" {
  description = "Administrator login for SQL Server"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,127}$", var.sql_admin_login))
    error_message = "SQL admin login must start with a letter and be 1-128 characters long."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for SQL Server"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = var.sql_admin_password == "" || can(regex("^.{8,128}$", var.sql_admin_password))
    error_message = "SQL admin password must be 8-128 characters long if provided."
  }
}

variable "sql_database_sku" {
  description = "SKU for the SQL Database"
  type        = string
  default     = "S1"
  
  validation {
    condition = contains([
      "Basic", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S9", "S12",
      "P1", "P2", "P4", "P6", "P11", "P15", "GP_Gen5_2", "GP_Gen5_4",
      "GP_Gen5_8", "GP_Gen5_16", "GP_Gen5_32", "GP_Gen5_80", "BC_Gen5_2",
      "BC_Gen5_4", "BC_Gen5_8", "BC_Gen5_16", "BC_Gen5_32", "BC_Gen5_80"
    ], var.sql_database_sku)
    error_message = "SQL Database SKU must be a valid Azure SQL Database service tier."
  }
}

variable "sql_database_max_size_gb" {
  description = "Maximum size of the SQL Database in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.sql_database_max_size_gb >= 1 && var.sql_database_max_size_gb <= 4096
    error_message = "SQL Database max size must be between 1 and 4096 GB."
  }
}

# Function App Configuration Variables
variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
  default     = ""
  
  validation {
    condition     = var.function_app_name == "" || can(regex("^[a-zA-Z0-9-]{2,60}$", var.function_app_name))
    error_message = "Function App name must be 2-60 characters long and contain only alphanumeric characters and hyphens."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3",
      "S1", "S2", "S3", "B1", "B2", "B3", "F1", "D1"
    ], var.function_app_service_plan_sku)
    error_message = "Function App Service Plan SKU must be a valid Azure App Service plan tier."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~4", "~3"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be ~4 or ~3."
  }
}

variable "function_app_dotnet_version" {
  description = ".NET version for the Function App"
  type        = string
  default     = "6.0"
  
  validation {
    condition     = contains(["6.0", "7.0", "8.0"], var.function_app_dotnet_version)
    error_message = ".NET version must be 6.0, 7.0, or 8.0."
  }
}

# Storage Account Configuration Variables
variable "storage_account_name" {
  description = "Name of the Storage Account"
  type        = string
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Performance tier of the Storage Account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage Account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the Storage Account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage Account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Application Insights Configuration Variables
variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = ""
  
  validation {
    condition     = var.application_insights_name == "" || can(regex("^[a-zA-Z0-9-._]{1,260}$", var.application_insights_name))
    error_message = "Application Insights name must be 1-260 characters long and contain only alphanumeric characters, hyphens, periods, and underscores."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period for Application Insights in days"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention days must be 30, 60, 90, 120, 180, 270, 365, 550, or 730."
  }
}

# Log Analytics Configuration Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  type        = string
  default     = ""
  
  validation {
    condition     = var.log_analytics_workspace_name == "" || can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics Workspace name must be 4-63 characters long and contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium", "Standard", "Standalone", "Unlimited"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, PerNode, PerGB2018, Premium, Standard, Standalone, or Unlimited."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Key Vault Configuration Variables
variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = ""
  
  validation {
    condition     = var.key_vault_name == "" || can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters long and contain only alphanumeric characters and hyphens."
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

# Networking Configuration Variables
variable "virtual_network_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "Virtual Network address space must contain at least one CIDR block."
  }
}

variable "service_fabric_subnet_address_prefix" {
  description = "Address prefix for the Service Fabric subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.service_fabric_subnet_address_prefix, 0))
    error_message = "Service Fabric subnet address prefix must be a valid CIDR block."
  }
}

variable "function_app_subnet_address_prefix" {
  description = "Address prefix for the Function App subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.function_app_subnet_address_prefix, 0))
    error_message = "Function App subnet address prefix must be a valid CIDR block."
  }
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "microservices-orchestration"
    Purpose     = "azure-service-fabric-durable-functions"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_service_fabric_monitoring" {
  description = "Enable monitoring for Service Fabric cluster"
  type        = bool
  default     = true
}

variable "enable_sql_threat_detection" {
  description = "Enable Advanced Threat Protection for SQL Database"
  type        = bool
  default     = true
}

variable "enable_key_vault_soft_delete" {
  description = "Enable soft delete for Key Vault"
  type        = bool
  default     = true
}

variable "enable_public_network_access" {
  description = "Enable public network access for resources"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}