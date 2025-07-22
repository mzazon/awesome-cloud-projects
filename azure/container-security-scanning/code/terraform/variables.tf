# Input Variables for Container Security Scanning Infrastructure
# This file defines all configurable parameters for the deployment

# Basic Configuration Variables
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "container-security"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Azure Container Registry Configuration
variable "acr_sku" {
  description = "SKU for Azure Container Registry (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "acr_admin_enabled" {
  description = "Enable admin user for Azure Container Registry"
  type        = bool
  default     = false
}

variable "acr_public_network_access_enabled" {
  description = "Enable public network access for Azure Container Registry"
  type        = bool
  default     = true
}

variable "acr_quarantine_policy_enabled" {
  description = "Enable quarantine policy for Azure Container Registry"
  type        = bool
  default     = true
}

variable "acr_trust_policy_enabled" {
  description = "Enable trust policy for Azure Container Registry"
  type        = bool
  default     = true
}

variable "acr_retention_policy_days" {
  description = "Number of days to retain untagged manifests"
  type        = number
  default     = 7
  
  validation {
    condition = var.acr_retention_policy_days >= 0 && var.acr_retention_policy_days <= 365
    error_message = "Retention policy days must be between 0 and 365."
  }
}

# Microsoft Defender Configuration
variable "defender_for_containers_enabled" {
  description = "Enable Microsoft Defender for Containers"
  type        = bool
  default     = true
}

variable "defender_for_container_registries_enabled" {
  description = "Enable Microsoft Defender for Container Registries"
  type        = bool
  default     = true
}

# Azure Kubernetes Service Configuration
variable "create_aks_cluster" {
  description = "Create an AKS cluster for testing deployments"
  type        = bool
  default     = true
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 2
  
  validation {
    condition = var.aks_node_count >= 1 && var.aks_node_count <= 10
    error_message = "AKS node count must be between 1 and 10."
  }
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.27"
}

# Log Analytics Configuration
variable "log_retention_days" {
  description = "Number of days to retain log data"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Azure Policy Configuration
variable "enable_policy_enforcement" {
  description = "Enable Azure Policy enforcement for container security"
  type        = bool
  default     = true
}

variable "policy_enforcement_mode" {
  description = "Policy enforcement mode (Default, DoNotEnforce)"
  type        = string
  default     = "Default"
  
  validation {
    condition = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "Policy enforcement mode must be Default or DoNotEnforce."
  }
}

# Service Principal Configuration
variable "create_service_principal" {
  description = "Create a service principal for DevOps integration"
  type        = bool
  default     = true
}

variable "service_principal_name" {
  description = "Name for the service principal"
  type        = string
  default     = "sp-acr-devops"
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Container Security Scanning"
    Environment = "Demo"
    Owner       = "DevSecOps Team"
  }
}

# Network Security Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access the container registry"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for container registry (requires Premium SKU)"
  type        = bool
  default     = false
}

# Alert Configuration
variable "enable_security_alerts" {
  description = "Enable security alerts for container vulnerabilities"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses for security alerts"
  type        = list(string)
  default     = []
}

# Data Export Configuration
variable "enable_data_export" {
  description = "Enable data export for security findings"
  type        = bool
  default     = false
}

variable "data_export_storage_account_name" {
  description = "Storage account name for data export"
  type        = string
  default     = ""
}