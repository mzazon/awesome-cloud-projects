# Azure Container Registry and Container Instances Terraform Variables
# This file defines all input variables for the Azure container deployment
# Variables enable customization and reusability of the Terraform configuration

# Resource naming and location variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group where all resources will be created"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 && 
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._\\(\\)-]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters and can contain letters, numbers, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Israel Central", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia", "India Central", "India South", "India West"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (dev, test, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Container Registry configuration variables
variable "container_registry_name" {
  description = "Name of the Azure Container Registry (must be globally unique)"
  type        = string
  default     = null
  
  validation {
    condition = var.container_registry_name == null || (
      length(var.container_registry_name) >= 5 && 
      length(var.container_registry_name) <= 50 &&
      can(regex("^[a-zA-Z0-9]+$", var.container_registry_name))
    )
    error_message = "Registry name must be 5-50 characters and contain only alphanumeric characters."
  }
}

variable "container_registry_sku" {
  description = "SKU tier for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
}

variable "enable_admin_user" {
  description = "Enable admin user for simplified container registry authentication"
  type        = bool
  default     = true
}

# Container Instance configuration variables
variable "container_instance_name" {
  description = "Name of the Azure Container Instance"
  type        = string
  default     = null
  
  validation {
    condition = var.container_instance_name == null || (
      length(var.container_instance_name) >= 1 && 
      length(var.container_instance_name) <= 63 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.container_instance_name))
    )
    error_message = "Container instance name must be 1-63 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "container_image" {
  description = "Container image to deploy (will be built and pushed to ACR)"
  type        = string
  default     = "simple-nginx"
}

variable "container_image_tag" {
  description = "Tag for the container image"
  type        = string
  default     = "v1"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.container_image_tag))
    error_message = "Container image tag must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

# Container resource allocation variables
variable "container_cpu" {
  description = "Number of CPU cores to allocate to the container"
  type        = number
  default     = 1
  
  validation {
    condition     = var.container_cpu >= 0.1 && var.container_cpu <= 4
    error_message = "Container CPU must be between 0.1 and 4 cores."
  }
}

variable "container_memory" {
  description = "Amount of memory in GB to allocate to the container"
  type        = number
  default     = 1.5
  
  validation {
    condition     = var.container_memory >= 0.1 && var.container_memory <= 16
    error_message = "Container memory must be between 0.1 and 16 GB."
  }
}

variable "container_port" {
  description = "Port number that the container exposes"
  type        = number
  default     = 80
  
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "container_protocol" {
  description = "Network protocol for the container port"
  type        = string
  default     = "TCP"
  
  validation {
    condition     = contains(["TCP", "UDP"], var.container_protocol)
    error_message = "Container protocol must be TCP or UDP."
  }
}

# DNS and networking variables
variable "dns_name_label" {
  description = "DNS name label for the container group (creates a FQDN)"
  type        = string
  default     = null
  
  validation {
    condition = var.dns_name_label == null || (
      length(var.dns_name_label) >= 1 && 
      length(var.dns_name_label) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.dns_name_label))
    )
    error_message = "DNS name label must be 1-63 characters, lowercase, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "ip_address_type" {
  description = "IP address type for the container group"
  type        = string
  default     = "Public"
  
  validation {
    condition     = contains(["Public", "Private", "None"], var.ip_address_type)
    error_message = "IP address type must be Public, Private, or None."
  }
}

variable "restart_policy" {
  description = "Restart policy for the container group"
  type        = string
  default     = "Always"
  
  validation {
    condition     = contains(["Always", "Never", "OnFailure"], var.restart_policy)
    error_message = "Restart policy must be Always, Never, or OnFailure."
  }
}

# Operating system configuration
variable "os_type" {
  description = "Operating system type for the container group"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "OS type must be Linux or Windows."
  }
}

# Resource tagging variables
variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "Container Demo"
    ManagedBy   = "Terraform"
    Application = "Simple Web Container"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.tags : can(regex("^[a-zA-Z0-9 ._-]+$", k)) && 
                            can(regex("^[a-zA-Z0-9 ._-]*$", v)) &&
                            length(k) <= 512 && 
                            length(v) <= 256
    ])
    error_message = "Tag keys and values must contain only letters, numbers, spaces, periods, underscores, and hyphens. Keys max 512 chars, values max 256 chars."
  }
}

# Random suffix configuration
variable "use_random_suffix" {
  description = "Whether to append a random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of the random suffix to append to resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}