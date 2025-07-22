# Variables for Azure Data Share and Service Fabric Cross-Organization Collaboration

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "South India", "Central India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "datashare"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "data_provider_org" {
  description = "Name of the data provider organization"
  type        = string
  default     = "provider"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.data_provider_org))
    error_message = "Organization name must contain only lowercase letters and numbers."
  }
}

variable "data_consumer_org" {
  description = "Name of the data consumer organization"
  type        = string
  default     = "consumer"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.data_consumer_org))
    error_message = "Organization name must contain only lowercase letters and numbers."
  }
}

# Service Fabric Cluster Configuration
variable "service_fabric_cluster_size" {
  description = "Number of nodes in the Service Fabric cluster"
  type        = number
  default     = 5
  
  validation {
    condition     = var.service_fabric_cluster_size >= 3 && var.service_fabric_cluster_size <= 100
    error_message = "Service Fabric cluster size must be between 3 and 100 nodes."
  }
}

variable "service_fabric_vm_size" {
  description = "Virtual machine size for Service Fabric cluster nodes"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_B2s", "Standard_B2ms", "Standard_B4ms",
      "Standard_F2s_v2", "Standard_F4s_v2", "Standard_F8s_v2"
    ], var.service_fabric_vm_size)
    error_message = "VM size must be a valid Azure VM size suitable for Service Fabric."
  }
}

variable "service_fabric_os_version" {
  description = "Operating system version for Service Fabric cluster"
  type        = string
  default     = "WindowsServer2019Datacenter"
  
  validation {
    condition = contains([
      "WindowsServer2019Datacenter",
      "WindowsServer2022Datacenter",
      "UbuntuServer1804",
      "UbuntuServer2004"
    ], var.service_fabric_os_version)
    error_message = "OS version must be a supported Service Fabric operating system."
  }
}

# Storage Configuration
variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_tier" {
  description = "Default access tier for storage accounts"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_tier)
    error_message = "Storage tier must be either Hot or Cool."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "enable_soft_delete" {
  description = "Enable soft delete for Key Vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "DataShareDemo"
    Solution    = "CrossOrgCollaboration"
    ManagedBy   = "Terraform"
  }
}

# Network Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure connectivity"
  type        = bool
  default     = true
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "Virtual network address space must not be empty."
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type = object({
    service_fabric = string
    private_endpoints = string
    gateway = string
  })
  default = {
    service_fabric    = "10.0.1.0/24"
    private_endpoints = "10.0.2.0/24"
    gateway          = "10.0.3.0/24"
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # In production, restrict this to known IP ranges
}

variable "enable_azure_ad_authentication" {
  description = "Enable Azure AD authentication for data sharing"
  type        = bool
  default     = true
}

# Data Share Configuration
variable "data_share_terms_of_use" {
  description = "Terms of use for data sharing agreements"
  type        = string
  default     = "Data for internal use only. No redistribution allowed. Compliance with organizational data governance policies required."
}

variable "sample_data_enabled" {
  description = "Create sample dataset for demonstration purposes"
  type        = bool
  default     = true
}

# Monitoring and Alerting Configuration
variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for the solution"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses to receive monitoring alerts"
  type        = list(string)
  default     = []
}