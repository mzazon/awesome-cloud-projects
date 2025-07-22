# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORKING CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "virtual_network_address_space" {
  description = "The address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.virtual_network_address_space : can(cidrhost(cidr, 0))
    ])
    error_message = "All virtual network address spaces must be valid CIDR blocks."
  }
}

variable "ase_subnet_address_prefix" {
  description = "The address prefix for the App Service Environment subnet (/24 minimum required)"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition = can(cidrhost(var.ase_subnet_address_prefix, 0)) && tonumber(split("/", var.ase_subnet_address_prefix)[1]) <= 24
    error_message = "ASE subnet address prefix must be a valid CIDR block with /24 or larger."
  }
}

variable "nat_subnet_address_prefix" {
  description = "The address prefix for the NAT Gateway subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition = can(cidrhost(var.nat_subnet_address_prefix, 0))
    error_message = "NAT subnet address prefix must be a valid CIDR block."
  }
}

variable "support_subnet_address_prefix" {
  description = "The address prefix for the support services subnet"
  type        = string
  default     = "10.0.3.0/24"
  
  validation {
    condition = can(cidrhost(var.support_subnet_address_prefix, 0))
    error_message = "Support subnet address prefix must be a valid CIDR block."
  }
}

variable "bastion_subnet_address_prefix" {
  description = "The address prefix for the Azure Bastion subnet (/26 minimum required)"
  type        = string
  default     = "10.0.4.0/26"
  
  validation {
    condition = can(cidrhost(var.bastion_subnet_address_prefix, 0)) && tonumber(split("/", var.bastion_subnet_address_prefix)[1]) <= 26
    error_message = "Bastion subnet address prefix must be a valid CIDR block with /26 or larger."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# APP SERVICE ENVIRONMENT CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "ase_zone_redundant" {
  description = "Enable zone redundancy for App Service Environment"
  type        = bool
  default     = true
}

variable "ase_front_end_scale_factor" {
  description = "Scale factor for ASE front end instances"
  type        = number
  default     = 15
  
  validation {
    condition = var.ase_front_end_scale_factor >= 15 && var.ase_front_end_scale_factor <= 50
    error_message = "ASE front end scale factor must be between 15 and 50."
  }
}

variable "app_service_plan_sku" {
  description = "The SKU for the App Service Plan in the ASE"
  type        = string
  default     = "I1v2"
  
  validation {
    condition = contains(["I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2"], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be one of the Isolated v2 SKUs: I1v2, I2v2, I3v2, I4v2, I5v2, I6v2."
  }
}

variable "app_service_plan_capacity" {
  description = "The number of instances for the App Service Plan"
  type        = number
  default     = 1
  
  validation {
    condition = var.app_service_plan_capacity >= 1 && var.app_service_plan_capacity <= 100
    error_message = "App Service Plan capacity must be between 1 and 100."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# WEB APPLICATION CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "web_app_runtime" {
  description = "The runtime stack for the web application"
  type        = string
  default     = "dotnet:8"
  
  validation {
    condition = contains(["dotnet:6", "dotnet:8", "java:11", "java:17", "node:18", "node:20", "python:3.9", "python:3.10", "python:3.11"], var.web_app_runtime)
    error_message = "Web app runtime must be a supported runtime version."
  }
}

variable "web_app_always_on" {
  description = "Enable always on for the web application"
  type        = bool
  default     = true
}

variable "web_app_https_only" {
  description = "Force HTTPS only for the web application"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# PRIVATE DNS CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "private_dns_zone_name" {
  description = "The name of the private DNS zone"
  type        = string
  default     = "enterprise.internal"
  
  validation {
    condition = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.private_dns_zone_name))
    error_message = "Private DNS zone name must be a valid domain name."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# NAT GATEWAY CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "nat_gateway_idle_timeout" {
  description = "The idle timeout for the NAT Gateway in minutes"
  type        = number
  default     = 10
  
  validation {
    condition = var.nat_gateway_idle_timeout >= 4 && var.nat_gateway_idle_timeout <= 120
    error_message = "NAT Gateway idle timeout must be between 4 and 120 minutes."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# BASTION CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "bastion_sku" {
  description = "The SKU for Azure Bastion"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Basic", "Standard"], var.bastion_sku)
    error_message = "Bastion SKU must be either Basic or Standard."
  }
}

variable "enable_bastion" {
  description = "Enable Azure Bastion deployment"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# MANAGEMENT VM CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "management_vm_size" {
  description = "The size of the management virtual machine"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = can(regex("^Standard_[A-Z][0-9]+[a-z]*_v[0-9]+$", var.management_vm_size))
    error_message = "Management VM size must be a valid Azure VM size."
  }
}

variable "management_vm_admin_username" {
  description = "The admin username for the management VM"
  type        = string
  default     = "azureuser"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.management_vm_admin_username))
    error_message = "Management VM admin username must start with a letter and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "management_vm_admin_password" {
  description = "The admin password for the management VM"
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
  
  validation {
    condition = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,}$", var.management_vm_admin_password))
    error_message = "Management VM admin password must be at least 12 characters long and contain uppercase, lowercase, numbers, and special characters."
  }
}

variable "enable_management_vm" {
  description = "Enable management VM deployment"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGGING CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "enterprise-isolation"
    Environment = "production"
    Tier        = "enterprise"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# NAMING CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "ase-enterprise"
  
  validation {
    condition = can(regex("^[a-z0-9-]{1,10}$", var.resource_prefix))
    error_message = "Resource prefix must be 1-10 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "use_random_suffix" {
  description = "Add random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}