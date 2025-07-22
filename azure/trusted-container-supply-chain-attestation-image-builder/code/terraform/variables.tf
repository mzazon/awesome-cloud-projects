# Variables for Azure Trusted Container Supply Chain Infrastructure

# Resource naming and location
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "container-supply-chain"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
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
      "Canada Central", "Canada East", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia",
      "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Container Supply Chain Security"
    Environment = "Demo"
    Terraform   = "true"
  }
}

# Random suffix configuration
variable "use_random_suffix" {
  description = "Whether to use a random suffix for globally unique resource names"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 3 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 3 and 8 characters."
  }
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "purge_key_vault_on_destroy" {
  description = "Whether to purge Key Vault on destroy (required for complete cleanup)"
  type        = bool
  default     = true
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault objects"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Container Registry configuration
variable "acr_sku" {
  description = "SKU for Azure Container Registry (Basic, Standard, Premium)"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "acr_admin_enabled" {
  description = "Whether to enable admin user for Container Registry"
  type        = bool
  default     = false
}

variable "acr_public_network_access_enabled" {
  description = "Whether public network access is allowed for Container Registry"
  type        = bool
  default     = true
}

variable "acr_quarantine_policy_enabled" {
  description = "Whether to enable quarantine policy for Container Registry"
  type        = bool
  default     = true
}

variable "acr_trust_policy_enabled" {
  description = "Whether to enable trust policy for Container Registry"
  type        = bool
  default     = true
}

variable "acr_retention_policy_days" {
  description = "Number of days to retain untagged manifests"
  type        = number
  default     = 7
  
  validation {
    condition     = var.acr_retention_policy_days >= 0 && var.acr_retention_policy_days <= 365
    error_message = "ACR retention policy days must be between 0 and 365."
  }
}

# Image Builder configuration
variable "image_builder_vm_size" {
  description = "VM size for Azure Image Builder"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = can(regex("^Standard_[A-Z][0-9]+[a-z]*_v[0-9]+$", var.image_builder_vm_size))
    error_message = "VM size must be a valid Azure VM size (e.g., Standard_D2s_v3)."
  }
}

variable "image_builder_os_disk_size_gb" {
  description = "OS disk size in GB for Image Builder"
  type        = number
  default     = 30
  
  validation {
    condition     = var.image_builder_os_disk_size_gb >= 30 && var.image_builder_os_disk_size_gb <= 1024
    error_message = "OS disk size must be between 30 and 1024 GB."
  }
}

variable "image_builder_build_timeout_minutes" {
  description = "Build timeout in minutes for Image Builder"
  type        = number
  default     = 60
  
  validation {
    condition     = var.image_builder_build_timeout_minutes >= 30 && var.image_builder_build_timeout_minutes <= 960
    error_message = "Build timeout must be between 30 and 960 minutes."
  }
}

# Source image configuration
variable "source_image_publisher" {
  description = "Publisher of the source image"
  type        = string
  default     = "Canonical"
}

variable "source_image_offer" {
  description = "Offer of the source image"
  type        = string
  default     = "0001-com-ubuntu-server-focal"
}

variable "source_image_sku" {
  description = "SKU of the source image"
  type        = string
  default     = "20_04-lts-gen2"
}

variable "source_image_version" {
  description = "Version of the source image"
  type        = string
  default     = "latest"
}

# Attestation configuration
variable "attestation_policy_format" {
  description = "Format of the attestation policy (Text or JWT)"
  type        = string
  default     = "Text"
  
  validation {
    condition     = contains(["Text", "JWT"], var.attestation_policy_format)
    error_message = "Attestation policy format must be either 'Text' or 'JWT'."
  }
}

# Signing key configuration
variable "signing_key_type" {
  description = "Type of signing key (RSA, EC)"
  type        = string
  default     = "RSA"
  
  validation {
    condition     = contains(["RSA", "EC"], var.signing_key_type)
    error_message = "Signing key type must be either 'RSA' or 'EC'."
  }
}

variable "signing_key_size" {
  description = "Size of RSA signing key (2048, 3072, 4096)"
  type        = number
  default     = 2048
  
  validation {
    condition     = contains([2048, 3072, 4096], var.signing_key_size)
    error_message = "RSA key size must be 2048, 3072, or 4096."
  }
}

variable "signing_key_curve" {
  description = "Curve for EC signing key (P-256, P-384, P-521)"
  type        = string
  default     = "P-256"
  
  validation {
    condition     = contains(["P-256", "P-384", "P-521"], var.signing_key_curve)
    error_message = "EC curve must be P-256, P-384, or P-521."
  }
}

# Network configuration
variable "create_virtual_network" {
  description = "Whether to create a virtual network for the resources"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Security configuration
variable "enable_rbac_authorization" {
  description = "Whether to enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

# Monitoring and logging
variable "enable_diagnostic_settings" {
  description = "Whether to enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_workspace_sku)
    error_message = "Log Analytics workspace SKU must be Free, PerNode, PerGB2018, or Standalone."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}