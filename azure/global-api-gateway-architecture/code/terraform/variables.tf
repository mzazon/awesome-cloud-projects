# Core configuration variables
variable "resource_group_name" {
  description = "Name of the resource group for all resources"
  type        = string
  default     = "rg-global-api-gateway"
}

variable "location" {
  description = "Primary Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "West Europe", "Southeast Asia",
      "UK South", "Japan East", "Australia East", "Central US"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports API Management Premium tier."
  }
}

variable "secondary_regions" {
  description = "List of secondary regions for multi-region deployment"
  type        = list(string)
  default     = ["West Europe", "Southeast Asia"]
  
  validation {
    condition     = length(var.secondary_regions) >= 1 && length(var.secondary_regions) <= 3
    error_message = "Must specify between 1 and 3 secondary regions."
  }
}

# Naming and tagging variables
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "global-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "multi-region-api-gateway"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# API Management configuration
variable "apim_sku_name" {
  description = "SKU name for API Management (Premium required for multi-region)"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = var.apim_sku_name == "Premium"
    error_message = "API Management must use Premium SKU for multi-region deployment."
  }
}

variable "apim_sku_capacity" {
  description = "Number of scale units for API Management in each region"
  type        = number
  default     = 1
  
  validation {
    condition     = var.apim_sku_capacity >= 1 && var.apim_sku_capacity <= 10
    error_message = "API Management capacity must be between 1 and 10 units."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "Contoso API Platform"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "api-team@contoso.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

variable "apim_enable_zone_redundancy" {
  description = "Enable zone redundancy for API Management"
  type        = bool
  default     = true
}

# Cosmos DB configuration
variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "Eventual", "Session", "BoundedStaleness", "Strong", "ConsistentPrefix"
    ], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, Session, BoundedStaleness, Strong, ConsistentPrefix."
  }
}

variable "cosmos_enable_multi_region_writes" {
  description = "Enable multi-region writes for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmos_throughput" {
  description = "Throughput (RU/s) for Cosmos DB containers"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "cosmos_enable_free_tier" {
  description = "Enable Cosmos DB free tier (limit one per subscription)"
  type        = bool
  default     = false
}

# Traffic Manager configuration
variable "traffic_manager_routing_method" {
  description = "Routing method for Traffic Manager"
  type        = string
  default     = "Performance"
  
  validation {
    condition = contains([
      "Performance", "Priority", "Weighted", "Geographic", "MultiValue", "Subnet"
    ], var.traffic_manager_routing_method)
    error_message = "Traffic Manager routing method must be one of: Performance, Priority, Weighted, Geographic, MultiValue, Subnet."
  }
}

variable "traffic_manager_ttl" {
  description = "TTL for Traffic Manager DNS responses"
  type        = number
  default     = 30
  
  validation {
    condition     = var.traffic_manager_ttl >= 30 && var.traffic_manager_ttl <= 2147483647
    error_message = "Traffic Manager TTL must be between 30 and 2147483647 seconds."
  }
}

# Monitoring configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for distributed tracing"
  type        = bool
  default     = true
}

# Security configuration
variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for API Management"
  type        = bool
  default     = true
}

variable "cosmos_enable_rbac" {
  description = "Enable RBAC for Cosmos DB access"
  type        = bool
  default     = true
}

# Custom domain configuration (optional)
variable "custom_domain_name" {
  description = "Custom domain name for the API gateway (optional)"
  type        = string
  default     = ""
}

variable "certificate_source" {
  description = "Source of SSL certificate for custom domain (KeyVault or Managed)"
  type        = string
  default     = "Managed"
  
  validation {
    condition     = contains(["KeyVault", "Managed"], var.certificate_source)
    error_message = "Certificate source must be either KeyVault or Managed."
  }
}

# Advanced configuration
variable "enable_client_certificate" {
  description = "Enable client certificate authentication"
  type        = bool
  default     = false
}

variable "virtual_network_type" {
  description = "Virtual network type for API Management (None, External, Internal)"
  type        = string
  default     = "None"
  
  validation {
    condition     = contains(["None", "External", "Internal"], var.virtual_network_type)
    error_message = "Virtual network type must be None, External, or Internal."
  }
}