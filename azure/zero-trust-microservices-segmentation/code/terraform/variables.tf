# Variables for Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones
# These variables allow customization of the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group for all resources"
  type        = string
  default     = "rg-advanced-network-segmentation"
  
  validation {
    condition     = length(var.resource_group_name) <= 90 && can(regex("^[a-zA-Z0-9._()-]+$", var.resource_group_name))
    error_message = "Resource group name must be <= 90 characters and contain only alphanumeric, period, underscore, hyphen, and parentheses."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Central India", "South India", "Japan East",
      "Japan West", "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "advanced-networking"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be <= 20 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

# Virtual Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.vnet_address_space) > 0
    error_message = "At least one address space must be specified for the virtual network."
  }
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for AKS cluster subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_endpoints_subnet_address_prefix" {
  description = "Address prefix for private endpoints subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# AKS Cluster Configuration
variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-service-mesh-cluster"
  
  validation {
    condition     = length(var.aks_cluster_name) <= 63 && can(regex("^[a-z0-9-]+$", var.aks_cluster_name))
    error_message = "AKS cluster name must be <= 63 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format 'x.y' (e.g., '1.28')."
  }
}

variable "aks_node_count" {
  description = "Initial number of nodes in the AKS cluster"
  type        = number
  default     = 3
  
  validation {
    condition     = var.aks_node_count >= 1 && var.aks_node_count <= 100
    error_message = "AKS node count must be between 1 and 100."
  }
}

variable "aks_node_vm_size" {
  description = "VM size for AKS cluster nodes"
  type        = string
  default     = "Standard_D4s_v3"
  
  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_D2s_v4", "Standard_D4s_v4", "Standard_D8s_v4", "Standard_D16s_v4",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3"
    ], var.aks_node_vm_size)
    error_message = "VM size must be a valid Azure VM size suitable for AKS."
  }
}

variable "aks_min_count" {
  description = "Minimum number of nodes for cluster autoscaler"
  type        = number
  default     = 2
  
  validation {
    condition     = var.aks_min_count >= 1 && var.aks_min_count <= 50
    error_message = "Minimum node count must be between 1 and 50."
  }
}

variable "aks_max_count" {
  description = "Maximum number of nodes for cluster autoscaler"
  type        = number
  default     = 10
  
  validation {
    condition     = var.aks_max_count >= 1 && var.aks_max_count <= 100
    error_message = "Maximum node count must be between 1 and 100."
  }
}

# DNS Configuration
variable "dns_zone_name" {
  description = "Name of the private DNS zone for internal service discovery"
  type        = string
  default     = "company.internal"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.dns_zone_name))
    error_message = "DNS zone name must contain only lowercase letters, numbers, dots, and hyphens."
  }
}

# Application Gateway Configuration
variable "app_gateway_name" {
  description = "Name of the Application Gateway"
  type        = string
  default     = "agw-service-mesh"
  
  validation {
    condition     = length(var.app_gateway_name) <= 80 && can(regex("^[a-zA-Z0-9-_]+$", var.app_gateway_name))
    error_message = "Application Gateway name must be <= 80 characters and contain only alphanumeric, hyphens, and underscores."
  }
}

variable "app_gateway_sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "WAF_v2"
  
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.app_gateway_sku_name)
    error_message = "Application Gateway SKU must be Standard_v2 or WAF_v2."
  }
}

variable "app_gateway_sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "WAF_v2"
  
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.app_gateway_sku_tier)
    error_message = "Application Gateway SKU tier must be Standard_v2 or WAF_v2."
  }
}

variable "app_gateway_capacity" {
  description = "Capacity (number of instances) for Application Gateway"
  type        = number
  default     = 2
  
  validation {
    condition     = var.app_gateway_capacity >= 1 && var.app_gateway_capacity <= 125
    error_message = "Application Gateway capacity must be between 1 and 125."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "log-advanced-networking"
  
  validation {
    condition     = length(var.log_analytics_workspace_name) <= 63 && can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be <= 63 characters and contain only alphanumeric and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_retention_in_days" {
  description = "Number of days to retain log data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_in_days >= 7 && var.log_retention_in_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# Service Mesh Configuration
variable "enable_istio_addon" {
  description = "Enable Istio service mesh addon for AKS"
  type        = bool
  default     = true
}

variable "istio_version" {
  description = "Version of Istio to deploy (asm-1-17, asm-1-18, asm-1-19)"
  type        = string
  default     = "asm-1-19"
  
  validation {
    condition     = contains(["asm-1-17", "asm-1-18", "asm-1-19"], var.istio_version)
    error_message = "Istio version must be one of the supported ASM versions."
  }
}

# Application Configuration
variable "deploy_sample_applications" {
  description = "Whether to deploy sample applications for testing"
  type        = bool
  default     = true
}

variable "enable_monitoring_addons" {
  description = "Whether to deploy monitoring addons (Prometheus, Grafana, Kiali)"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_azure_policy" {
  description = "Enable Azure Policy addon for AKS"
  type        = bool
  default     = true
}

variable "enable_azure_rbac" {
  description = "Enable Azure RBAC for Kubernetes authorization"
  type        = bool
  default     = true
}

variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy (deprecated, use Pod Security Standards)"
  type        = bool
  default     = false
}

# Network Security
variable "enable_private_cluster" {
  description = "Enable private AKS cluster (API server not accessible from internet)"
  type        = bool
  default     = false
}

variable "authorized_ip_ranges" {
  description = "IP ranges authorized to access the Kubernetes API server"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip_range in var.authorized_ip_ranges : can(cidrhost(ip_range, 0))
    ])
    error_message = "All authorized IP ranges must be valid CIDR blocks."
  }
}

# Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Advanced Network Segmentation"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Purpose     = "Service Mesh Demo"
  }
}