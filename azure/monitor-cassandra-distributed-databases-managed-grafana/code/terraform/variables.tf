# Core Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Z][a-z]+ [A-Z][a-z]+$|^[A-Z][a-z]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cassandra-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name can only contain alphanumeric characters and hyphens."
  }
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "cassandra_subnet_address_prefix" {
  description = "Address prefix for the Cassandra subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Cassandra Configuration
variable "cassandra_admin_password" {
  description = "Administrator password for Cassandra cluster"
  type        = string
  sensitive   = true
  
  validation {
    condition     = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,}$", var.cassandra_admin_password))
    error_message = "Password must be at least 12 characters with uppercase, lowercase, number, and special character."
  }
}

variable "cassandra_version" {
  description = "Version of Apache Cassandra to deploy"
  type        = string
  default     = "4.0"
  
  validation {
    condition     = contains(["3.11", "4.0"], var.cassandra_version)
    error_message = "Cassandra version must be either 3.11 or 4.0."
  }
}

variable "datacenter_node_count" {
  description = "Number of nodes in the Cassandra datacenter"
  type        = number
  default     = 3
  
  validation {
    condition     = var.datacenter_node_count >= 1 && var.datacenter_node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "datacenter_sku" {
  description = "SKU for Cassandra datacenter nodes"
  type        = string
  default     = "Standard_DS14_v2"
  
  validation {
    condition = contains([
      "Standard_DS13_v2", "Standard_DS14_v2", "Standard_E8s_v3", 
      "Standard_E16s_v3", "Standard_E32s_v3"
    ], var.datacenter_sku)
    error_message = "SKU must be a valid Cassandra node size."
  }
}

# Grafana Configuration
variable "grafana_sku" {
  description = "SKU for Azure Managed Grafana"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Essential", "Standard"], var.grafana_sku)
    error_message = "Grafana SKU must be either Essential or Standard."
  }
}

variable "grafana_api_key_enabled" {
  description = "Enable API key authentication for Grafana"
  type        = bool
  default     = true
}

variable "grafana_deterministic_outbound_ip_enabled" {
  description = "Enable deterministic outbound IP for Grafana"
  type        = bool
  default     = false
}

variable "grafana_public_network_access_enabled" {
  description = "Enable public network access for Grafana"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "PerNode", "Premium", "Standard", 
      "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Retention days must be between 7 and 730."
  }
}

# Alert Configuration
variable "alert_enabled" {
  description = "Enable Azure Monitor alerts"
  type        = bool
  default     = true
}

variable "cpu_alert_threshold" {
  description = "CPU usage threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alert_threshold >= 1 && var.cpu_alert_threshold <= 100
    error_message = "CPU alert threshold must be between 1 and 100 percent."
  }
}

variable "alert_evaluation_frequency" {
  description = "How often to evaluate alert conditions (ISO 8601 duration)"
  type        = string
  default     = "PT1M"
  
  validation {
    condition     = can(regex("^PT[0-9]+[MH]$", var.alert_evaluation_frequency))
    error_message = "Evaluation frequency must be in ISO 8601 format (e.g., PT1M, PT5M, PT1H)."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (ISO 8601 duration)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = can(regex("^PT[0-9]+[MH]$", var.alert_window_size))
    error_message = "Window size must be in ISO 8601 format (e.g., PT5M, PT15M, PT1H)."
  }
}

variable "notification_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "ops@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

# Resource Tags
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose     = "monitoring"
    Environment = "demo"
    Project     = "cassandra-monitoring"
    ManagedBy   = "terraform"
  }
}