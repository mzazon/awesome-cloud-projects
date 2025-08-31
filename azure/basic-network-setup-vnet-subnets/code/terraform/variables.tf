# Variable definitions for the Basic Network Setup Terraform configuration
# These variables allow customization of the deployment without modifying the main configuration

# Core Azure configuration variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"

  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

# Resource naming variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group (will have random suffix added if not provided)"
  type        = string
  default     = ""
}

variable "virtual_network_name" {
  description = "Name of the Azure Virtual Network (will have random suffix added if not provided)"
  type        = string
  default     = ""
}

# Network configuration variables
variable "virtual_network_address_space" {
  description = "Address space for the Virtual Network in CIDR notation"
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition = alltrue([
      for cidr in var.virtual_network_address_space : can(cidrhost(cidr, 0))
    ])
    error_message = "All address spaces must be valid CIDR blocks."
  }
}

# Subnet configuration variables
variable "frontend_subnet_name" {
  description = "Name of the frontend subnet for web-facing resources"
  type        = string
  default     = "subnet-frontend"
}

variable "frontend_subnet_address_prefix" {
  description = "Address prefix for the frontend subnet in CIDR notation"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.frontend_subnet_address_prefix, 0))
    error_message = "Frontend subnet address prefix must be a valid CIDR block."
  }
}

variable "backend_subnet_name" {
  description = "Name of the backend subnet for application servers"
  type        = string
  default     = "subnet-backend"
}

variable "backend_subnet_address_prefix" {
  description = "Address prefix for the backend subnet in CIDR notation"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.backend_subnet_address_prefix, 0))
    error_message = "Backend subnet address prefix must be a valid CIDR block."
  }
}

variable "database_subnet_name" {
  description = "Name of the database subnet for data tier resources"
  type        = string
  default     = "subnet-database"
}

variable "database_subnet_address_prefix" {
  description = "Address prefix for the database subnet in CIDR notation"
  type        = string
  default     = "10.0.3.0/24"

  validation {
    condition     = can(cidrhost(var.database_subnet_address_prefix, 0))
    error_message = "Database subnet address prefix must be a valid CIDR block."
  }
}

# Network Security Group configuration variables
variable "frontend_allowed_ports" {
  description = "List of ports to allow for inbound traffic to the frontend subnet"
  type        = list(string)
  default     = ["80", "443"]

  validation {
    condition = alltrue([
      for port in var.frontend_allowed_ports : can(tonumber(port)) && tonumber(port) >= 1 && tonumber(port) <= 65535
    ])
    error_message = "All ports must be valid port numbers between 1 and 65535."
  }
}

variable "backend_application_port" {
  description = "Port number for backend application traffic from frontend"
  type        = string
  default     = "8080"

  validation {
    condition     = can(tonumber(var.backend_application_port)) && tonumber(var.backend_application_port) >= 1 && tonumber(var.backend_application_port) <= 65535
    error_message = "Backend application port must be a valid port number between 1 and 65535."
  }
}

variable "database_port" {
  description = "Port number for database traffic from backend (e.g., 5432 for PostgreSQL, 3306 for MySQL)"
  type        = string
  default     = "5432"

  validation {
    condition     = can(tonumber(var.database_port)) && tonumber(var.database_port) >= 1 && tonumber(var.database_port) <= 65535
    error_message = "Database port must be a valid port number between 1 and 65535."
  }
}

# Tagging variables for resource organization and cost management
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    purpose = "recipe"
    tier    = "networking"
  }

  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

# Random suffix configuration
variable "use_random_suffix" {
  description = "Whether to append a random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}