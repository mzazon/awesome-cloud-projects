# Variable definitions for Azure Stack HCI and Azure Arc edge computing infrastructure
# These variables allow customization of the deployment for different environments

# Basic Configuration Variables
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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West", "Korea Central",
      "Southeast Asia", "East Asia", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for edge infrastructure"
  type        = string
  default     = "rg-edge-infrastructure"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "edge-computing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Azure Stack HCI Configuration
variable "hci_cluster_name" {
  description = "Name of the Azure Stack HCI cluster"
  type        = string
  default     = ""
  
  validation {
    condition     = var.hci_cluster_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.hci_cluster_name))
    error_message = "HCI cluster name must contain only letters, numbers, and hyphens."
  }
}

variable "hci_node_count" {
  description = "Number of nodes in the Azure Stack HCI cluster"
  type        = number
  default     = 2
  
  validation {
    condition     = var.hci_node_count >= 2 && var.hci_node_count <= 16
    error_message = "HCI cluster must have between 2 and 16 nodes."
  }
}

variable "hci_storage_type" {
  description = "Storage type for Azure Stack HCI cluster"
  type        = string
  default     = "StorageSpacesDirect"
  
  validation {
    condition     = contains(["StorageSpacesDirect", "ExternalStorage"], var.hci_storage_type)
    error_message = "Storage type must be StorageSpacesDirect or ExternalStorage."
  }
}

# Azure Arc Configuration
variable "arc_resource_name" {
  description = "Name for Azure Arc connected machine resource"
  type        = string
  default     = ""
  
  validation {
    condition     = var.arc_resource_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.arc_resource_name))
    error_message = "Arc resource name must contain only letters, numbers, and hyphens."
  }
}

variable "enable_arc_kubernetes" {
  description = "Enable Azure Arc for Kubernetes clusters"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version for Arc-enabled clusters"
  type        = string
  default     = "1.28.5"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in semantic version format (e.g., 1.28.5)."
  }
}

# Monitoring and Logging Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
  
  validation {
    condition     = var.log_analytics_workspace_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must contain only letters, numbers, and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid option."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for application monitoring"
  type        = bool
  default     = true
}

# Storage Configuration
variable "storage_account_name" {
  description = "Name of the storage account for edge data synchronization"
  type        = string
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || (length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24 && can(regex("^[a-z0-9]+$", var.storage_account_name)))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be a valid Azure storage redundancy option."
  }
}

variable "storage_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_tier)
    error_message = "Storage tier must be Standard or Premium."
  }
}

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Security and Governance Configuration
variable "enable_azure_policy" {
  description = "Enable Azure Policy for governance"
  type        = bool
  default     = true
}

variable "enable_security_center" {
  description = "Enable Azure Security Center monitoring"
  type        = bool
  default     = true
}

variable "enable_defender_for_cloud" {
  description = "Enable Microsoft Defender for Cloud"
  type        = bool
  default     = false
}

variable "enable_key_vault" {
  description = "Enable Azure Key Vault for secrets management"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

# Network Configuration
variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "At least one address space must be specified for the virtual network."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the default subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for Azure services"
  type        = bool
  default     = true
}

# Resource Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "EdgeComputing"
    Solution    = "AzureStackHCI-AzureArc"
    ManagedBy   = "Terraform"
  }
}

# Cost Management
variable "enable_cost_management" {
  description = "Enable cost management and budgets"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD for cost alerts"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

# Backup and Disaster Recovery
variable "enable_backup" {
  description = "Enable Azure Backup for supported resources"
  type        = bool
  default     = true
}

variable "backup_policy_type" {
  description = "Type of backup policy to apply"
  type        = string
  default     = "V2"
  
  validation {
    condition     = contains(["V1", "V2"], var.backup_policy_type)
    error_message = "Backup policy type must be V1 or V2."
  }
}

# Advanced Configuration
variable "enable_arc_data_services" {
  description = "Enable Azure Arc data services"
  type        = bool
  default     = false
}

variable "enable_arc_ml" {
  description = "Enable Azure Arc machine learning"
  type        = bool
  default     = false
}

variable "custom_location_name" {
  description = "Name for Azure Arc custom location"
  type        = string
  default     = ""
  
  validation {
    condition     = var.custom_location_name == "" || can(regex("^[a-zA-Z0-9-]+$", var.custom_location_name))
    error_message = "Custom location name must contain only letters, numbers, and hyphens."
  }
}

# Edge Workload Configuration
variable "deploy_sample_workloads" {
  description = "Deploy sample edge workloads for demonstration"
  type        = bool
  default     = true
}

variable "workload_namespace" {
  description = "Kubernetes namespace for edge workloads"
  type        = string
  default     = "edge-apps"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workload_namespace))
    error_message = "Workload namespace must contain only lowercase letters, numbers, and hyphens."
  }
}