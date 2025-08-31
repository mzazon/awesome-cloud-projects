# Variables for Azure Infrastructure Inventory with Resource Graph
# This file defines input variables for customizing the deployment

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
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters and numbers only."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "inventory"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project_name))
    error_message = "Project name must be 2-15 characters, lowercase letters and numbers only."
  }
}

variable "owner" {
  description = "Owner of the resources for tagging and governance"
  type        = string
  default     = "DevOps Team"
}

variable "cost_center" {
  description = "Cost center for resource tagging and chargeback"
  type        = string
  default     = "IT-001"
}

variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Infrastructure Inventory Demo"
    Compliance  = "Required"
    DataClass   = "Internal"
  }
}

variable "create_sample_resources" {
  description = "Whether to create sample resources for inventory demonstration"
  type        = bool
  default     = true
}

variable "sample_vm_size" {
  description = "Size of the sample virtual machine for inventory demonstration"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B2s", "Standard_B4ms",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3"
    ], var.sample_vm_size)
    error_message = "VM size must be a valid Azure VM size for demonstration purposes."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Azure Monitor and diagnostic settings"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain logs and monitoring data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 365
    error_message = "Retention days must be between 7 and 365."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access sample resources"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Note: Restrict this in production environments
  
  validation {
    condition     = length(var.allowed_ip_ranges) > 0
    error_message = "At least one IP range must be specified."
  }
}

variable "enable_resource_graph_queries" {
  description = "Whether to output sample Resource Graph queries for testing"
  type        = bool
  default     = true
}

variable "governance_policies" {
  description = "Configuration for governance and compliance policies"
  type = object({
    require_tags           = bool
    allowed_locations      = list(string)
    require_encryption     = bool
    audit_public_access    = bool
  })
  
  default = {
    require_tags           = true
    allowed_locations      = ["East US", "West US 2", "Central US"]
    require_encryption     = true
    audit_public_access    = true
  }
}

variable "inventory_schedule" {
  description = "Configuration for automated inventory reporting"
  type = object({
    enabled               = bool
    frequency_minutes     = number
    export_to_storage     = bool
    alert_on_changes      = bool
  })
  
  default = {
    enabled               = true
    frequency_minutes     = 60
    export_to_storage     = true
    alert_on_changes      = false
  }
}