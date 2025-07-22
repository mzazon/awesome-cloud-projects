# Variables for Azure Virtual Desktop Cost Optimization Infrastructure
# This file defines all configurable parameters for the deployment

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US", "North Central US", "South Central US",
      "West Europe", "North Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast", "Japan East", "Japan West"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure Virtual Desktop."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "avd-cost-opt"
  
  validation {
    condition     = length(var.resource_prefix) <= 15 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be 15 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AVD-Cost-Optimization"
    Environment = "Demo"
    Purpose     = "Virtual-Desktop-Cost-Management"
    ManagedBy   = "Terraform"
  }
}

# Virtual Machine Scale Set Configuration
variable "vmss_instance_count" {
  description = "Initial number of VM instances in the scale set"
  type        = number
  default     = 2
  
  validation {
    condition     = var.vmss_instance_count >= 1 && var.vmss_instance_count <= 20
    error_message = "Instance count must be between 1 and 20."
  }
}

variable "vmss_sku" {
  description = "VM SKU for the scale set instances"
  type        = string
  default     = "Standard_D2s_v3"
  
  validation {
    condition = contains([
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_B2s", "Standard_B4ms", "Standard_B8ms"
    ], var.vmss_sku)
    error_message = "VM SKU must be a supported Azure Virtual Desktop VM size."
  }
}

variable "admin_username" {
  description = "Administrator username for VMs"
  type        = string
  default     = "avdadmin"
  
  validation {
    condition     = length(var.admin_username) >= 3 && length(var.admin_username) <= 20
    error_message = "Admin username must be between 3 and 20 characters."
  }
}

variable "admin_password" {
  description = "Administrator password for VMs"
  type        = string
  sensitive   = true
  default     = "SecureP@ssw0rd123!"
  
  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "Admin password must be at least 12 characters long."
  }
}

# Auto-scaling Configuration
variable "autoscale_min_capacity" {
  description = "Minimum number of VM instances for auto-scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.autoscale_min_capacity >= 1 && var.autoscale_min_capacity <= 10
    error_message = "Minimum capacity must be between 1 and 10."
  }
}

variable "autoscale_max_capacity" {
  description = "Maximum number of VM instances for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.autoscale_max_capacity >= 2 && var.autoscale_max_capacity <= 50
    error_message = "Maximum capacity must be between 2 and 50."
  }
}

variable "autoscale_default_capacity" {
  description = "Default number of VM instances for auto-scaling"
  type        = number
  default     = 2
  
  validation {
    condition     = var.autoscale_default_capacity >= 1 && var.autoscale_default_capacity <= 20
    error_message = "Default capacity must be between 1 and 20."
  }
}

# AVD Configuration
variable "avd_host_pool_type" {
  description = "Type of AVD host pool (Pooled or Personal)"
  type        = string
  default     = "Pooled"
  
  validation {
    condition     = contains(["Pooled", "Personal"], var.avd_host_pool_type)
    error_message = "Host pool type must be either Pooled or Personal."
  }
}

variable "avd_load_balancer_type" {
  description = "Load balancer algorithm for AVD host pool"
  type        = string
  default     = "BreadthFirst"
  
  validation {
    condition     = contains(["BreadthFirst", "DepthFirst"], var.avd_load_balancer_type)
    error_message = "Load balancer type must be either BreadthFirst or DepthFirst."
  }
}

variable "avd_max_session_limit" {
  description = "Maximum sessions per VM for pooled host pools"
  type        = number
  default     = 10
  
  validation {
    condition     = var.avd_max_session_limit >= 1 && var.avd_max_session_limit <= 25
    error_message = "Max session limit must be between 1 and 25."
  }
}

# Cost Management Configuration
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost management"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.budget_amount >= 100 && var.budget_amount <= 50000
    error_message = "Budget amount must be between 100 and 50,000 USD."
  }
}

variable "budget_alert_threshold_actual" {
  description = "Threshold percentage for actual cost alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold_actual >= 50 && var.budget_alert_threshold_actual <= 100
    error_message = "Actual cost alert threshold must be between 50 and 100 percent."
  }
}

variable "budget_alert_threshold_forecast" {
  description = "Threshold percentage for forecasted cost alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_alert_threshold_forecast >= 80 && var.budget_alert_threshold_forecast <= 150
    error_message = "Forecast cost alert threshold must be between 80 and 150 percent."
  }
}

# Networking Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the AVD subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Department Configuration for Cost Attribution
variable "departments" {
  description = "List of departments for cost attribution and tagging"
  type = list(object({
    name        = string
    cost_center = string
    budget      = number
  }))
  default = [
    {
      name        = "finance"
      cost_center = "100"
      budget      = 300
    },
    {
      name        = "engineering"
      cost_center = "200"
      budget      = 500
    },
    {
      name        = "marketing"
      cost_center = "300"
      budget      = 200
    }
  ]
}

# Logic App Configuration
variable "logic_app_enabled" {
  description = "Whether to deploy Logic App for cost optimization automation"
  type        = bool
  default     = true
}

variable "function_app_enabled" {
  description = "Whether to deploy Function App for Reserved Instance analysis"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}