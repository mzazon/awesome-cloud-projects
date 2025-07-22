# General Configuration
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South",
      "UK West", "West Europe", "North Europe", "France Central",
      "Germany West Central", "Switzerland North", "Norway East",
      "Sweden Central", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India",
      "South India", "Japan East", "Japan West", "Korea Central",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,90}$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must be 1-90 characters and contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "golden-image"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,50}$", var.project_name))
    error_message = "Project name must be 1-50 characters and contain only letters, numbers, and hyphens."
  }
}

# Network Configuration
variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.hub_vnet_address_space) > 0
    error_message = "Hub VNet address space must contain at least one CIDR block."
  }
}

variable "build_vnet_address_space" {
  description = "Address space for the build virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = length(var.build_vnet_address_space) > 0
    error_message = "Build VNet address space must contain at least one CIDR block."
  }
}

variable "resolver_inbound_subnet_address_prefix" {
  description = "Address prefix for DNS resolver inbound subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.resolver_inbound_subnet_address_prefix, 0))
    error_message = "Resolver inbound subnet address prefix must be a valid CIDR block."
  }
}

variable "resolver_outbound_subnet_address_prefix" {
  description = "Address prefix for DNS resolver outbound subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.resolver_outbound_subnet_address_prefix, 0))
    error_message = "Resolver outbound subnet address prefix must be a valid CIDR block."
  }
}

variable "build_subnet_address_prefix" {
  description = "Address prefix for build subnet"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.build_subnet_address_prefix, 0))
    error_message = "Build subnet address prefix must be a valid CIDR block."
  }
}

# VM Image Builder Configuration
variable "vm_image_builder_build_timeout" {
  description = "Build timeout in minutes for VM Image Builder"
  type        = number
  default     = 80
  
  validation {
    condition     = var.vm_image_builder_build_timeout >= 60 && var.vm_image_builder_build_timeout <= 240
    error_message = "Build timeout must be between 60 and 240 minutes."
  }
}

variable "vm_image_builder_vm_size" {
  description = "VM size for the image builder"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_D2s_v4", "Standard_D4s_v4", "Standard_D8s_v4",
      "Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5"
    ], var.vm_image_builder_vm_size)
    error_message = "VM size must be a valid Azure VM size for image building."
  }
}

variable "vm_image_builder_os_disk_size" {
  description = "OS disk size in GB for the image builder VM"
  type        = number
  default     = 30
  
  validation {
    condition     = var.vm_image_builder_os_disk_size >= 30 && var.vm_image_builder_os_disk_size <= 1024
    error_message = "OS disk size must be between 30 and 1024 GB."
  }
}

variable "source_image_publisher" {
  description = "Publisher of the source image"
  type        = string
  default     = "Canonical"
  
  validation {
    condition     = length(var.source_image_publisher) > 0
    error_message = "Source image publisher cannot be empty."
  }
}

variable "source_image_offer" {
  description = "Offer of the source image"
  type        = string
  default     = "0001-com-ubuntu-server-focal"
  
  validation {
    condition     = length(var.source_image_offer) > 0
    error_message = "Source image offer cannot be empty."
  }
}

variable "source_image_sku" {
  description = "SKU of the source image"
  type        = string
  default     = "20_04-lts-gen2"
  
  validation {
    condition     = length(var.source_image_sku) > 0
    error_message = "Source image SKU cannot be empty."
  }
}

variable "source_image_version" {
  description = "Version of the source image"
  type        = string
  default     = "latest"
  
  validation {
    condition     = length(var.source_image_version) > 0
    error_message = "Source image version cannot be empty."
  }
}

# Azure Compute Gallery Configuration
variable "compute_gallery_description" {
  description = "Description for the Azure Compute Gallery"
  type        = string
  default     = "Corporate Golden Image Gallery"
  
  validation {
    condition     = length(var.compute_gallery_description) <= 1000
    error_message = "Compute gallery description must be 1000 characters or less."
  }
}

variable "gallery_image_definition_publisher" {
  description = "Publisher for the gallery image definition"
  type        = string
  default     = "CorporateIT"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,128}$", var.gallery_image_definition_publisher))
    error_message = "Gallery image definition publisher must be 1-128 characters and contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "gallery_image_definition_offer" {
  description = "Offer for the gallery image definition"
  type        = string
  default     = "UbuntuServer"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,128}$", var.gallery_image_definition_offer))
    error_message = "Gallery image definition offer must be 1-128 characters and contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "gallery_image_definition_sku" {
  description = "SKU for the gallery image definition"
  type        = string
  default     = "20.04-LTS-Hardened"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,128}$", var.gallery_image_definition_sku))
    error_message = "Gallery image definition SKU must be 1-128 characters and contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "gallery_image_definition_description" {
  description = "Description for the gallery image definition"
  type        = string
  default     = "Corporate hardened Ubuntu 20.04 LTS server image"
  
  validation {
    condition     = length(var.gallery_image_definition_description) <= 1000
    error_message = "Gallery image definition description must be 1000 characters or less."
  }
}

variable "replication_regions" {
  description = "List of regions for image replication"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.replication_regions) <= 10
    error_message = "Maximum of 10 replication regions allowed."
  }
}

variable "storage_account_type" {
  description = "Storage account type for image replication"
  type        = string
  default     = "Standard_LRS"
  
  validation {
    condition     = contains(["Standard_LRS", "Standard_ZRS", "Premium_LRS"], var.storage_account_type)
    error_message = "Storage account type must be one of: Standard_LRS, Standard_ZRS, Premium_LRS."
  }
}

# DNS Configuration
variable "dns_forwarding_rules" {
  description = "List of DNS forwarding rules for on-premises domains"
  type = list(object({
    name            = string
    domain          = string
    target_servers  = list(string)
  }))
  default = []
  
  validation {
    condition     = length(var.dns_forwarding_rules) <= 25
    error_message = "Maximum of 25 DNS forwarding rules allowed."
  }
}

# Custom Image Configuration
variable "custom_image_scripts" {
  description = "List of custom scripts to run during image building"
  type = list(object({
    name        = string
    script_type = string
    inline      = list(string)
  }))
  default = []
  
  validation {
    condition     = length(var.custom_image_scripts) <= 20
    error_message = "Maximum of 20 custom scripts allowed."
  }
}

variable "enable_security_hardening" {
  description = "Enable security hardening during image build"
  type        = bool
  default     = true
}

variable "enable_monitoring_tools" {
  description = "Enable monitoring tools installation during image build"
  type        = bool
  default     = true
}

variable "enable_compliance_configuration" {
  description = "Enable compliance configuration during image build"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Purpose   = "golden-image-pipeline"
    ManagedBy = "terraform"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags allowed."
  }
}