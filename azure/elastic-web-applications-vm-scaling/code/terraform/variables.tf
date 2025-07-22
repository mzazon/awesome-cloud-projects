# Variable definitions for Azure auto-scaling web application infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-autoscale-web-app"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  validation {
    condition = can(regex("^(East US|West US|Central US|North Europe|West Europe|Southeast Asia|East Asia)$", var.location))
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "webapp"
}

variable "vm_sku" {
  description = "SKU for Virtual Machine Scale Set instances"
  type        = string
  default     = "Standard_B2s"
  validation {
    condition = can(regex("^Standard_[A-Z0-9]+[a-z]*$", var.vm_sku))
    error_message = "VM SKU must be a valid Azure VM size."
  }
}

variable "admin_username" {
  description = "Administrator username for VM instances"
  type        = string
  default     = "azureuser"
  validation {
    condition     = length(var.admin_username) >= 3 && length(var.admin_username) <= 20
    error_message = "Admin username must be between 3 and 20 characters."
  }
}

variable "vmss_initial_capacity" {
  description = "Initial number of VM instances in the scale set"
  type        = number
  default     = 2
  validation {
    condition     = var.vmss_initial_capacity >= 1 && var.vmss_initial_capacity <= 100
    error_message = "Initial capacity must be between 1 and 100."
  }
}

variable "vmss_min_capacity" {
  description = "Minimum number of VM instances in the scale set"
  type        = number
  default     = 2
  validation {
    condition     = var.vmss_min_capacity >= 1 && var.vmss_min_capacity <= 100
    error_message = "Minimum capacity must be between 1 and 100."
  }
}

variable "vmss_max_capacity" {
  description = "Maximum number of VM instances in the scale set"
  type        = number
  default     = 10
  validation {
    condition     = var.vmss_max_capacity >= 1 && var.vmss_max_capacity <= 1000
    error_message = "Maximum capacity must be between 1 and 1000."
  }
}

variable "scale_out_cpu_threshold" {
  description = "CPU percentage threshold for scale-out operations"
  type        = number
  default     = 70
  validation {
    condition     = var.scale_out_cpu_threshold >= 1 && var.scale_out_cpu_threshold <= 100
    error_message = "Scale-out CPU threshold must be between 1 and 100."
  }
}

variable "scale_in_cpu_threshold" {
  description = "CPU percentage threshold for scale-in operations"
  type        = number
  default     = 30
  validation {
    condition     = var.scale_in_cpu_threshold >= 1 && var.scale_in_cpu_threshold <= 100
    error_message = "Scale-in CPU threshold must be between 1 and 100."
  }
}

variable "scale_out_capacity_change" {
  description = "Number of instances to add during scale-out"
  type        = number
  default     = 2
  validation {
    condition     = var.scale_out_capacity_change >= 1 && var.scale_out_capacity_change <= 10
    error_message = "Scale-out capacity change must be between 1 and 10."
  }
}

variable "scale_in_capacity_change" {
  description = "Number of instances to remove during scale-in"
  type        = number
  default     = 1
  validation {
    condition     = var.scale_in_capacity_change >= 1 && var.scale_in_capacity_change <= 10
    error_message = "Scale-in capacity change must be between 1 and 10."
  }
}

variable "cooldown_duration" {
  description = "Cooldown period in minutes for auto-scaling operations"
  type        = string
  default     = "PT5M"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "load_balancer_sku" {
  description = "SKU for the Azure Load Balancer"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard"], var.load_balancer_sku)
    error_message = "Load balancer SKU must be Basic or Standard."
  }
}

variable "health_probe_interval" {
  description = "Interval in seconds for health probe checks"
  type        = number
  default     = 15
  validation {
    condition     = var.health_probe_interval >= 5 && var.health_probe_interval <= 2147483647
    error_message = "Health probe interval must be at least 5 seconds."
  }
}

variable "health_probe_threshold" {
  description = "Number of consecutive probe failures before marking instance unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.health_probe_threshold >= 1 && var.health_probe_threshold <= 2147483647
    error_message = "Health probe threshold must be at least 1."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_auto_scaling_alerts" {
  description = "Enable monitoring alerts for auto-scaling events"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default = {
    Purpose = "recipe"
  }
}