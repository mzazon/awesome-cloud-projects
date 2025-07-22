# Variables for Azure Private 5G Network deployment

# Basic Configuration
variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure region for deploying resources. Must support Azure Private 5G Core and Operator Nexus services."
  
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "centralus", "northcentralus", "southcentralus",
      "westeurope", "northeurope", "uksouth", "ukwest",
      "southeastasia", "eastasia", "japaneast", "japanwest",
      "australiaeast", "australiasoutheast"
    ], var.location)
    error_message = "Location must be a supported Azure region for Private 5G Core services."
  }
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Environment name (e.g., dev, staging, production)"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  type        = string
  default     = "private5g"
  description = "Project name used for resource naming and tagging"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be 20 characters or less."
  }
}

# Mobile Network Configuration
variable "mobile_network_name" {
  type        = string
  default     = "mn-manufacturing"
  description = "Name for the mobile network resource"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.mobile_network_name)) && length(var.mobile_network_name) <= 64
    error_message = "Mobile network name must contain only alphanumeric characters, hyphens, and underscores, and be 64 characters or less."
  }
}

variable "plmn_mcc" {
  type        = string
  default     = "310"
  description = "Mobile Country Code (MCC) for the PLMN identifier. 310 is for United States."
  
  validation {
    condition     = can(regex("^[0-9]{3}$", var.plmn_mcc))
    error_message = "MCC must be a 3-digit numeric string."
  }
}

variable "plmn_mnc" {
  type        = string
  default     = "950"
  description = "Mobile Network Code (MNC) for the PLMN identifier. Must be coordinated with spectrum regulations."
  
  validation {
    condition     = can(regex("^[0-9]{2,3}$", var.plmn_mnc))
    error_message = "MNC must be a 2 or 3-digit numeric string."
  }
}

# Site Configuration
variable "site_name" {
  type        = string
  default     = "site-factory01"
  description = "Name for the manufacturing site where 5G core will be deployed"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.site_name)) && length(var.site_name) <= 64
    error_message = "Site name must contain only alphanumeric characters, hyphens, and underscores, and be 64 characters or less."
  }
}

# Network Interface Configuration
variable "access_interface_ip" {
  type        = string
  default     = "192.168.1.10"
  description = "IP address for the N2 access interface connecting to radio equipment"
  
  validation {
    condition     = can(cidrhost("${var.access_interface_ip}/32", 0))
    error_message = "Access interface IP must be a valid IPv4 address."
  }
}

variable "access_interface_subnet" {
  type        = string
  default     = "192.168.1.0/24"
  description = "Subnet for the N2 access interface"
  
  validation {
    condition     = can(cidrhost(var.access_interface_subnet, 0))
    error_message = "Access interface subnet must be a valid CIDR notation."
  }
}

variable "access_interface_gateway" {
  type        = string
  default     = "192.168.1.1"
  description = "Gateway IP for the access interface"
  
  validation {
    condition     = can(cidrhost("${var.access_interface_gateway}/32", 0))
    error_message = "Access interface gateway must be a valid IPv4 address."
  }
}

# Data Network Configuration
variable "ot_systems_dns_servers" {
  type        = list(string)
  default     = ["10.1.0.10", "10.1.0.11"]
  description = "DNS servers for OT (Operational Technology) systems data network"
  
  validation {
    condition = alltrue([
      for ip in var.ot_systems_dns_servers : can(cidrhost("${ip}/32", 0))
    ])
    error_message = "All DNS server IPs must be valid IPv4 addresses."
  }
}

variable "it_systems_dns_servers" {
  type        = list(string)
  default     = ["10.2.0.10", "10.2.0.11"]
  description = "DNS servers for IT systems data network"
  
  validation {
    condition = alltrue([
      for ip in var.it_systems_dns_servers : can(cidrhost("${ip}/32", 0))
    ])
    error_message = "All DNS server IPs must be valid IPv4 addresses."
  }
}

variable "ot_user_plane_ip" {
  type        = string
  default     = "10.1.0.100"
  description = "User plane data interface IP for OT systems"
  
  validation {
    condition     = can(cidrhost("${var.ot_user_plane_ip}/32", 0))
    error_message = "OT user plane IP must be a valid IPv4 address."
  }
}

variable "it_user_plane_ip" {
  type        = string
  default     = "10.2.0.100"
  description = "User plane data interface IP for IT systems"
  
  validation {
    condition     = can(cidrhost("${var.it_user_plane_ip}/32", 0))
    error_message = "IT user plane IP must be a valid IPv4 address."
  }
}

# Network Slice Configuration
variable "enable_network_slices" {
  type        = bool
  default     = true
  description = "Enable creation of network slices for different use cases"
}

variable "network_slices" {
  type = list(object({
    name        = string
    description = string
    sst         = number
    sd          = string
  }))
  default = [
    {
      name        = "slice-critical-iot"
      description = "Network slice for mission-critical IoT devices requiring ultra-low latency"
      sst         = 1
      sd          = "000001"
    },
    {
      name        = "slice-massive-iot"
      description = "Network slice for massive IoT sensor deployments"
      sst         = 2
      sd          = "000002"
    },
    {
      name        = "slice-video"
      description = "Network slice for video surveillance and streaming"
      sst         = 3
      sd          = "000003"
    }
  ]
  description = "Configuration for network slices. SST (Slice/Service Type): 1=eMBB, 2=URLLC, 3=mMTC"
  
  validation {
    condition = alltrue([
      for slice in var.network_slices : slice.sst >= 1 && slice.sst <= 3
    ])
    error_message = "SST (Slice/Service Type) must be between 1 and 3."
  }
  
  validation {
    condition = alltrue([
      for slice in var.network_slices : can(regex("^[0-9]{6}$", slice.sd))
    ])
    error_message = "SD (Slice Differentiator) must be a 6-digit hexadecimal string."
  }
}

# Packet Core Configuration
variable "packet_core_sku" {
  type        = string
  default     = "G0"
  description = "SKU for the packet core control plane (G0, G1, G2, G5, G10)"
  
  validation {
    condition     = contains(["G0", "G1", "G2", "G5", "G10"], var.packet_core_sku)
    error_message = "Packet core SKU must be one of: G0, G1, G2, G5, G10."
  }
}

variable "enable_local_diagnostics" {
  type        = bool
  default     = true
  description = "Enable local diagnostics with Azure AD authentication"
}

# IoT and Analytics Configuration
variable "iot_hub_sku" {
  type        = string
  default     = "S1"
  description = "SKU for IoT Hub (F1, S1, S2, S3)"
  
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, S1, S2, S3."
  }
}

variable "enable_iot_integration" {
  type        = bool
  default     = true
  description = "Enable IoT Hub and Device Provisioning Service integration"
}

variable "enable_analytics" {
  type        = bool
  default     = true
  description = "Enable Log Analytics workspace and monitoring"
}

# Container Registry Configuration
variable "container_registry_sku" {
  type        = string
  default     = "Standard"
  description = "SKU for Azure Container Registry (Basic, Standard, Premium)"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be one of: Basic, Standard, Premium."
  }
}

variable "enable_container_registry" {
  type        = bool
  default     = true
  description = "Enable Azure Container Registry for edge workloads"
}

# Security Configuration
variable "enable_private_endpoints" {
  type        = bool
  default     = false
  description = "Enable private endpoints for Azure services (requires virtual network configuration)"
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "List of IP ranges allowed to access management services (CIDR notation)"
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR notation."
  }
}

# Edge Computing Configuration
variable "enable_edge_workloads" {
  type        = bool
  default     = true
  description = "Enable deployment of sample edge computing workloads"
}

variable "edge_workload_replicas" {
  type        = number
  default     = 3
  description = "Number of replicas for edge analytics workloads"
  
  validation {
    condition     = var.edge_workload_replicas >= 1 && var.edge_workload_replicas <= 10
    error_message = "Edge workload replicas must be between 1 and 10."
  }
}

# Resource Tagging
variable "tags" {
  type        = map(string)
  default = {
    Purpose     = "Private5G"
    Environment = "Production"
    Workload    = "Manufacturing"
    Technology  = "5G-Core"
  }
  description = "Tags to apply to all resources"
  
  validation {
    condition = alltrue([
      for key, value in var.tags : can(regex("^[a-zA-Z0-9-_. ]+$", key)) && can(regex("^[a-zA-Z0-9-_. ]+$", value))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters, hyphens, underscores, periods, and spaces."
  }
}

# Cost Management
variable "auto_shutdown_enabled" {
  type        = bool
  default     = false
  description = "Enable automatic shutdown schedules for non-production environments"
}

variable "backup_retention_days" {
  type        = number
  default     = 30
  description = "Number of days to retain backup data"
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 2555
    error_message = "Backup retention days must be between 1 and 2555."
  }
}