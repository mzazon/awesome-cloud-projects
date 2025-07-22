# Variables for Azure hybrid database connectivity infrastructure

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-hybrid-db-connectivity"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "India Central",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "hybrid-db"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Virtual Network Configuration
variable "vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = can([for cidr in var.vnet_address_space : cidrhost(cidr, 0)])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for the Gateway subnet (required for ExpressRoute Gateway)"
  type        = string
  default     = "10.1.1.0/27"
  
  validation {
    condition     = can(cidrhost(var.gateway_subnet_address_prefix, 0))
    error_message = "Gateway subnet address prefix must be a valid CIDR block."
  }
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for the Application Gateway subnet"
  type        = string
  default     = "10.1.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.appgw_subnet_address_prefix, 0))
    error_message = "Application Gateway subnet address prefix must be a valid CIDR block."
  }
}

variable "database_subnet_address_prefix" {
  description = "Address prefix for the database subnet"
  type        = string
  default     = "10.1.3.0/24"
  
  validation {
    condition     = can(cidrhost(var.database_subnet_address_prefix, 0))
    error_message = "Database subnet address prefix must be a valid CIDR block."
  }
}

variable "management_subnet_address_prefix" {
  description = "Address prefix for the management subnet"
  type        = string
  default     = "10.1.4.0/24"
  
  validation {
    condition     = can(cidrhost(var.management_subnet_address_prefix, 0))
    error_message = "Management subnet address prefix must be a valid CIDR block."
  }
}

variable "bastion_subnet_address_prefix" {
  description = "Address prefix for the Azure Bastion subnet (must be named AzureBastionSubnet)"
  type        = string
  default     = "10.1.5.0/26"
  
  validation {
    condition     = can(cidrhost(var.bastion_subnet_address_prefix, 0))
    error_message = "Bastion subnet address prefix must be a valid CIDR block."
  }
}

# ExpressRoute Configuration
variable "expressroute_circuit_id" {
  description = "Resource ID of the existing ExpressRoute circuit (optional - leave empty to skip connection)"
  type        = string
  default     = ""
}

variable "expressroute_gateway_sku" {
  description = "SKU for the ExpressRoute Gateway"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "HighPerformance", "UltraPerformance"], var.expressroute_gateway_sku)
    error_message = "ExpressRoute Gateway SKU must be Standard, HighPerformance, or UltraPerformance."
  }
}

# Application Gateway Configuration
variable "application_gateway_sku" {
  description = "SKU for the Application Gateway"
  type        = string
  default     = "WAF_v2"
  
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.application_gateway_sku)
    error_message = "Application Gateway SKU must be Standard_v2 or WAF_v2."
  }
}

variable "application_gateway_capacity" {
  description = "Number of Application Gateway instances"
  type        = number
  default     = 2
  
  validation {
    condition     = var.application_gateway_capacity >= 1 && var.application_gateway_capacity <= 125
    error_message = "Application Gateway capacity must be between 1 and 125."
  }
}

# PostgreSQL Configuration
variable "postgresql_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "GP_Standard_D2s_v3"
  
  validation {
    condition = can(regex("^(B_Standard_B1ms|B_Standard_B2s|GP_Standard_D2s_v3|GP_Standard_D4s_v3|GP_Standard_D8s_v3|GP_Standard_D16s_v3|GP_Standard_D32s_v3|GP_Standard_D48s_v3|GP_Standard_D64s_v3|MO_Standard_E2s_v3|MO_Standard_E4s_v3|MO_Standard_E8s_v3|MO_Standard_E16s_v3|MO_Standard_E32s_v3|MO_Standard_E48s_v3|MO_Standard_E64s_v3)$", var.postgresql_sku_name))
    error_message = "PostgreSQL SKU name must be a valid Azure Database for PostgreSQL Flexible Server SKU."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be 11, 12, 13, 14, or 15."
  }
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage size in MB"
  type        = number
  default     = 131072
  
  validation {
    condition     = var.postgresql_storage_mb >= 32768 && var.postgresql_storage_mb <= 33554432
    error_message = "PostgreSQL storage must be between 32768 MB (32 GB) and 33554432 MB (32 TB)."
  }
}

variable "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL server"
  type        = string
  default     = "dbadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,63}$", var.postgresql_admin_username))
    error_message = "PostgreSQL admin username must start with a letter and be 3-64 characters long."
  }
}

variable "postgresql_admin_password" {
  description = "Administrator password for PostgreSQL server"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.postgresql_admin_password == null || can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{8,128}$", var.postgresql_admin_password))
    error_message = "PostgreSQL admin password must be 8-128 characters and contain lowercase, uppercase, digit, and special character."
  }
}

variable "postgresql_backup_retention_days" {
  description = "Backup retention period in days for PostgreSQL"
  type        = number
  default     = 7
  
  validation {
    condition     = var.postgresql_backup_retention_days >= 7 && var.postgresql_backup_retention_days <= 35
    error_message = "PostgreSQL backup retention must be between 7 and 35 days."
  }
}

variable "postgresql_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backup for PostgreSQL"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_on_premises_address_prefixes" {
  description = "List of on-premises address prefixes allowed to access the database"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition     = can([for cidr in var.allowed_on_premises_address_prefixes : cidrhost(cidr, 0)])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "enable_bastion" {
  description = "Enable Azure Bastion for secure management access"
  type        = bool
  default     = true
}

variable "enable_ddos_protection" {
  description = "Enable DDoS protection standard for the virtual network"
  type        = bool
  default     = false
}

# Monitoring and Logging
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_workspace_sku)
    error_message = "Log Analytics Workspace SKU must be a valid Azure SKU."
  }
}

variable "log_retention_in_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "HybridDBConnectivity"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}