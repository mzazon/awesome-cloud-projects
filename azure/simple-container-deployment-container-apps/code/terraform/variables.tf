# Core configuration variables
variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z][A-Za-z0-9 ]*[A-Za-z0-9]$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

# Container Apps Environment variables
variable "container_apps_environment_name" {
  description = "Name of the Container Apps environment (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

# Container App variables
variable "container_app_name" {
  description = "Name of the container application (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
  
  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "Container port must be between 1 and 65535."
  }
}

# Scaling configuration variables
variable "min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 25
    error_message = "Minimum replicas must be between 0 and 25."
  }
}

variable "max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 25
    error_message = "Maximum replicas must be between 1 and 25."
  }
}

# Resource allocation variables
variable "cpu_requests" {
  description = "CPU allocation for each container replica (in cores)"
  type        = number
  default     = 0.25
  
  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], var.cpu_requests)
    error_message = "CPU requests must be one of: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0."
  }
}

variable "memory_requests" {
  description = "Memory allocation for each container replica (in Gi)"
  type        = string
  default     = "0.5Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.memory_requests))
    error_message = "Memory requests must be in Gi format (e.g., 0.5Gi, 1Gi, 2Gi)."
  }
}

# Ingress configuration variables
variable "ingress_enabled" {
  description = "Enable external ingress for the container app"
  type        = bool
  default     = true
}

variable "ingress_allow_insecure" {
  description = "Allow insecure connections to the container app"
  type        = bool
  default     = false
}

# Tagging variables
variable "tags" {
  description = "Resource tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    environment = "demo"
    project     = "container-apps-quickstart"
  }
}

# Random suffix for unique resource naming
variable "random_suffix" {
  description = "Random suffix for resource names (if not provided, will be auto-generated)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.random_suffix == "" || can(regex("^[a-z0-9]{6}$", var.random_suffix))
    error_message = "Random suffix must be empty or 6 lowercase alphanumeric characters."
  }
}