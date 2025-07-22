# Variables for Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center
# Terraform variable definitions for GCP multi-cloud networking architecture

#------------------------------------------------------------------------------
# Project and Region Configuration
#------------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be specified."
  }
}

variable "region" {
  description = "The GCP region where regional resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and identification"
  type        = string
  default     = "production"
  
  validation {
    condition = contains([
      "development", "staging", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

#------------------------------------------------------------------------------
# Network Connectivity Center Configuration
#------------------------------------------------------------------------------

variable "ncc_hub_name" {
  description = "Name for the Network Connectivity Center hub"
  type        = string
  default     = "multi-cloud-hub"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.ncc_hub_name))
    error_message = "Hub name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a letter or number."
  }
}

#------------------------------------------------------------------------------
# VPC Network Names
#------------------------------------------------------------------------------

variable "hub_vpc_name" {
  description = "Base name for the hub VPC network (suffix will be added automatically)"
  type        = string
  default     = "hub-vpc"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.hub_vpc_name))
    error_message = "VPC name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a letter or number."
  }
}

variable "prod_vpc_name" {
  description = "Base name for the production VPC network (suffix will be added automatically)"
  type        = string
  default     = "prod-vpc"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.prod_vpc_name))
    error_message = "VPC name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a letter or number."
  }
}

variable "dev_vpc_name" {
  description = "Base name for the development VPC network (suffix will be added automatically)"
  type        = string
  default     = "dev-vpc"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.dev_vpc_name))
    error_message = "VPC name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a letter or number."
  }
}

variable "shared_vpc_name" {
  description = "Base name for the shared services VPC network (suffix will be added automatically)"
  type        = string
  default     = "shared-vpc"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.shared_vpc_name))
    error_message = "VPC name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a letter or number."
  }
}

#------------------------------------------------------------------------------
# Subnet CIDR Ranges
#------------------------------------------------------------------------------

variable "hub_subnet_cidr" {
  description = "CIDR range for the hub subnet"
  type        = string
  default     = "10.1.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.hub_subnet_cidr, 0))
    error_message = "Hub subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "prod_subnet_cidr" {
  description = "CIDR range for the production subnet"
  type        = string
  default     = "192.168.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.prod_subnet_cidr, 0))
    error_message = "Production subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "dev_subnet_cidr" {
  description = "CIDR range for the development subnet"
  type        = string
  default     = "192.168.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.dev_subnet_cidr, 0))
    error_message = "Development subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "shared_subnet_cidr" {
  description = "CIDR range for the shared services subnet"
  type        = string
  default     = "192.168.3.0/24"
  
  validation {
    condition     = can(cidrhost(var.shared_subnet_cidr, 0))
    error_message = "Shared services subnet CIDR must be a valid IPv4 CIDR block."
  }
}

#------------------------------------------------------------------------------
# BGP Configuration
#------------------------------------------------------------------------------

variable "hub_bgp_asn" {
  description = "BGP ASN for the hub router (must be private ASN 64512-65534 or 4200000000-4294967294)"
  type        = number
  default     = 64512
  
  validation {
    condition = (
      (var.hub_bgp_asn >= 64512 && var.hub_bgp_asn <= 65534) ||
      (var.hub_bgp_asn >= 4200000000 && var.hub_bgp_asn <= 4294967294)
    )
    error_message = "BGP ASN must be a private ASN in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "prod_bgp_asn" {
  description = "BGP ASN for the production router"
  type        = number
  default     = 64513
  
  validation {
    condition = (
      (var.prod_bgp_asn >= 64512 && var.prod_bgp_asn <= 65534) ||
      (var.prod_bgp_asn >= 4200000000 && var.prod_bgp_asn <= 4294967294)
    )
    error_message = "BGP ASN must be a private ASN in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "dev_bgp_asn" {
  description = "BGP ASN for the development router"
  type        = number
  default     = 64514
  
  validation {
    condition = (
      (var.dev_bgp_asn >= 64512 && var.dev_bgp_asn <= 65534) ||
      (var.dev_bgp_asn >= 4200000000 && var.dev_bgp_asn <= 4294967294)
    )
    error_message = "BGP ASN must be a private ASN in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "shared_bgp_asn" {
  description = "BGP ASN for the shared services router"
  type        = number
  default     = 64515
  
  validation {
    condition = (
      (var.shared_bgp_asn >= 64512 && var.shared_bgp_asn <= 65534) ||
      (var.shared_bgp_asn >= 4200000000 && var.shared_bgp_asn <= 4294967294)
    )
    error_message = "BGP ASN must be a private ASN in the range 64512-65534 or 4200000000-4294967294."
  }
}

variable "external_cloud_bgp_asn" {
  description = "BGP ASN for the external cloud provider"
  type        = number
  default     = 65001
  
  validation {
    condition = (
      (var.external_cloud_bgp_asn >= 64512 && var.external_cloud_bgp_asn <= 65534) ||
      (var.external_cloud_bgp_asn >= 4200000000 && var.external_cloud_bgp_asn <= 4294967294)
    )
    error_message = "BGP ASN must be a private ASN in the range 64512-65534 or 4200000000-4294967294."
  }
}

#------------------------------------------------------------------------------
# VPN Configuration
#------------------------------------------------------------------------------

variable "external_cloud_vpn_ip" {
  description = "Public IP address of the external cloud provider's VPN gateway"
  type        = string
  default     = "172.16.1.1"
  
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.external_cloud_vpn_ip))
    error_message = "External cloud VPN IP must be a valid IPv4 address."
  }
}

variable "vpn_shared_secret" {
  description = "Shared secret for VPN tunnel authentication (must be 1-256 characters)"
  type        = string
  default     = "your-shared-secret-here"
  sensitive   = true
  
  validation {
    condition     = length(var.vpn_shared_secret) >= 1 && length(var.vpn_shared_secret) <= 256
    error_message = "VPN shared secret must be between 1 and 256 characters."
  }
}

variable "external_cloud_bgp_peer_ip" {
  description = "BGP peer IP address for the external cloud provider (must be link-local)"
  type        = string
  default     = "169.254.1.2"
  
  validation {
    condition     = can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.external_cloud_bgp_peer_ip))
    error_message = "BGP peer IP must be a link-local address (169.254.x.x)."
  }
}

variable "vpn_tunnel_ip_range" {
  description = "IP range for the VPN tunnel interface (must be /30 link-local)"
  type        = string
  default     = "169.254.1.1/30"
  
  validation {
    condition = can(regex("^169\\.254\\.[0-9]{1,3}\\.[0-9]{1,3}/30$", var.vpn_tunnel_ip_range))
    error_message = "VPN tunnel IP range must be a /30 link-local subnet (169.254.x.x/30)."
  }
}

variable "enable_site_to_site_data_transfer" {
  description = "Enable site-to-site data transfer for the hybrid spoke"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Firewall Configuration
#------------------------------------------------------------------------------

variable "external_network_cidrs" {
  description = "List of external network CIDR ranges allowed for VPN access"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12"]
  
  validation {
    condition = alltrue([
      for cidr in var.external_network_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All external network CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "allowed_internal_cidrs" {
  description = "List of internal CIDR ranges allowed for cross-VPC communication"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_internal_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All internal CIDR ranges must be valid IPv4 CIDR blocks."
  }
}

#------------------------------------------------------------------------------
# Cloud NAT Configuration
#------------------------------------------------------------------------------

variable "enable_nat_logging" {
  description = "Enable logging for Cloud NAT gateways"
  type        = bool
  default     = true
}

variable "nat_log_filter" {
  description = "Filter for Cloud NAT logs (ERRORS_ONLY, TRANSLATIONS_ONLY, ALL)"
  type        = string
  default     = "ALL"
  
  validation {
    condition = contains([
      "ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"
    ], var.nat_log_filter)
    error_message = "NAT log filter must be one of: ERRORS_ONLY, TRANSLATIONS_ONLY, ALL."
  }
}

#------------------------------------------------------------------------------
# Resource Naming and Tagging
#------------------------------------------------------------------------------

variable "resource_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.resource_labels : can(regex("^[a-z][a-z0-9_-]*$", key))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
  
  validation {
    condition = alltrue([
      for key, value in var.resource_labels : length(value) <= 63
    ])
    error_message = "Label values must be 63 characters or less."
  }
}