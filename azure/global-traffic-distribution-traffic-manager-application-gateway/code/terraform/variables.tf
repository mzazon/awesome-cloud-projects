# Variables for global traffic distribution infrastructure

# General Configuration
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "global-traffic"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["prod", "dev", "staging", "test"], var.environment)
    error_message = "Environment must be one of: prod, dev, staging, test."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Purpose     = "global-traffic-distribution"
    ManagedBy   = "terraform"
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary Azure region for deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "East US 2", "West Central US", "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "France Central", "France South", "Germany West Central", "Germany North", "Norway East",
      "Norway West", "Switzerland North", "Switzerland West", "UK South", "UK West", "Sweden Central",
      "Sweden South", "Poland Central", "Italy North", "Israel Central", "Spain Central", "Austria East",
      "Greece Central", "Australia East", "Australia Southeast", "Australia Central", "Australia Central 2",
      "East Asia", "Southeast Asia", "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South", "South Africa North", "South Africa West", "UAE North", "UAE Central",
      "Qatar Central"
    ], var.primary_region)
    error_message = "Primary region must be a valid Azure region."
  }
}

variable "secondary_region" {
  description = "Secondary Azure region for deployment"
  type        = string
  default     = "UK South"
  
  validation {
    condition = contains([
      "East US", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "East US 2", "West Central US", "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "France Central", "France South", "Germany West Central", "Germany North", "Norway East",
      "Norway West", "Switzerland North", "Switzerland West", "UK South", "UK West", "Sweden Central",
      "Sweden South", "Poland Central", "Italy North", "Israel Central", "Spain Central", "Austria East",
      "Greece Central", "Australia East", "Australia Southeast", "Australia Central", "Australia Central 2",
      "East Asia", "Southeast Asia", "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South", "South Africa North", "South Africa West", "UAE North", "UAE Central",
      "Qatar Central"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid Azure region."
  }
}

variable "tertiary_region" {
  description = "Tertiary Azure region for deployment"
  type        = string
  default     = "Southeast Asia"
  
  validation {
    condition = contains([
      "East US", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "East US 2", "West Central US", "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "France Central", "France South", "Germany West Central", "Germany North", "Norway East",
      "Norway West", "Switzerland North", "Switzerland West", "UK South", "UK West", "Sweden Central",
      "Sweden South", "Poland Central", "Italy North", "Israel Central", "Spain Central", "Austria East",
      "Greece Central", "Australia East", "Australia Southeast", "Australia Central", "Australia Central 2",
      "East Asia", "Southeast Asia", "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South", "South Africa North", "South Africa West", "UAE North", "UAE Central",
      "Qatar Central"
    ], var.tertiary_region)
    error_message = "Tertiary region must be a valid Azure region."
  }
}

# Network Configuration
variable "vnet_address_spaces" {
  description = "Address spaces for virtual networks in each region"
  type = object({
    primary   = string
    secondary = string
    tertiary  = string
  })
  default = {
    primary   = "10.1.0.0/16"
    secondary = "10.2.0.0/16"
    tertiary  = "10.3.0.0/16"
  }
  
  validation {
    condition = alltrue([
      can(cidrhost(var.vnet_address_spaces.primary, 0)),
      can(cidrhost(var.vnet_address_spaces.secondary, 0)),
      can(cidrhost(var.vnet_address_spaces.tertiary, 0))
    ])
    error_message = "All VNET address spaces must be valid CIDR blocks."
  }
}

variable "appgw_subnet_prefixes" {
  description = "Subnet prefixes for Application Gateway subnets"
  type = object({
    primary   = string
    secondary = string
    tertiary  = string
  })
  default = {
    primary   = "10.1.1.0/24"
    secondary = "10.2.1.0/24"
    tertiary  = "10.3.1.0/24"
  }
}

variable "backend_subnet_prefixes" {
  description = "Subnet prefixes for backend subnets"
  type = object({
    primary   = string
    secondary = string
    tertiary  = string
  })
  default = {
    primary   = "10.1.2.0/24"
    secondary = "10.2.2.0/24"
    tertiary  = "10.3.2.0/24"
  }
}

# Application Gateway Configuration
variable "appgw_sku" {
  description = "SKU for Application Gateway"
  type        = string
  default     = "WAF_v2"
  
  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.appgw_sku)
    error_message = "Application Gateway SKU must be either Standard_v2 or WAF_v2."
  }
}

variable "appgw_capacity" {
  description = "Capacity (instance count) for Application Gateway"
  type        = number
  default     = 2
  
  validation {
    condition     = var.appgw_capacity >= 1 && var.appgw_capacity <= 125
    error_message = "Application Gateway capacity must be between 1 and 125."
  }
}

variable "appgw_zones" {
  description = "Availability zones for Application Gateway"
  type        = list(string)
  default     = ["1", "2", "3"]
  
  validation {
    condition     = alltrue([for zone in var.appgw_zones : contains(["1", "2", "3"], zone)])
    error_message = "Application Gateway zones must be valid availability zones (1, 2, or 3)."
  }
}

# WAF Configuration
variable "waf_mode" {
  description = "Web Application Firewall mode"
  type        = string
  default     = "Prevention"
  
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either Detection or Prevention."
  }
}

variable "waf_rule_set_type" {
  description = "WAF rule set type"
  type        = string
  default     = "OWASP"
  
  validation {
    condition     = contains(["OWASP", "Microsoft_BotManagerRuleSet"], var.waf_rule_set_type)
    error_message = "WAF rule set type must be either OWASP or Microsoft_BotManagerRuleSet."
  }
}

variable "waf_rule_set_version" {
  description = "WAF rule set version"
  type        = string
  default     = "3.2"
  
  validation {
    condition     = contains(["3.2", "3.1", "3.0"], var.waf_rule_set_version)
    error_message = "WAF rule set version must be 3.0, 3.1, or 3.2."
  }
}

# Virtual Machine Scale Set Configuration
variable "vmss_sku" {
  description = "SKU for Virtual Machine Scale Set instances"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition     = can(regex("^Standard_[A-Z][0-9]+[a-z]*$", var.vmss_sku))
    error_message = "VMSS SKU must be a valid Azure VM size."
  }
}

variable "vmss_instance_count" {
  description = "Initial instance count for Virtual Machine Scale Sets"
  type        = number
  default     = 2
  
  validation {
    condition     = var.vmss_instance_count >= 1 && var.vmss_instance_count <= 1000
    error_message = "VMSS instance count must be between 1 and 1000."
  }
}

variable "vmss_admin_username" {
  description = "Admin username for Virtual Machine Scale Set instances"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]*$", var.vmss_admin_username))
    error_message = "Admin username must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "vmss_zones" {
  description = "Availability zones for Virtual Machine Scale Sets"
  type        = list(string)
  default     = ["1", "2", "3"]
  
  validation {
    condition     = alltrue([for zone in var.vmss_zones : contains(["1", "2", "3"], zone)])
    error_message = "VMSS zones must be valid availability zones (1, 2, or 3)."
  }
}

# Traffic Manager Configuration
variable "traffic_manager_routing_method" {
  description = "Traffic Manager routing method"
  type        = string
  default     = "Performance"
  
  validation {
    condition     = contains(["Performance", "Priority", "Weighted", "Geographic", "MultiValue", "Subnet"], var.traffic_manager_routing_method)
    error_message = "Traffic Manager routing method must be one of: Performance, Priority, Weighted, Geographic, MultiValue, Subnet."
  }
}

variable "traffic_manager_ttl" {
  description = "Traffic Manager DNS TTL in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.traffic_manager_ttl >= 1 && var.traffic_manager_ttl <= 2147483647
    error_message = "Traffic Manager TTL must be between 1 and 2147483647 seconds."
  }
}

variable "traffic_manager_monitor_protocol" {
  description = "Traffic Manager monitor protocol"
  type        = string
  default     = "HTTP"
  
  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.traffic_manager_monitor_protocol)
    error_message = "Traffic Manager monitor protocol must be HTTP, HTTPS, or TCP."
  }
}

variable "traffic_manager_monitor_port" {
  description = "Traffic Manager monitor port"
  type        = number
  default     = 80
  
  validation {
    condition     = var.traffic_manager_monitor_port >= 1 && var.traffic_manager_monitor_port <= 65535
    error_message = "Traffic Manager monitor port must be between 1 and 65535."
  }
}

variable "traffic_manager_monitor_path" {
  description = "Traffic Manager monitor path"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/.*", var.traffic_manager_monitor_path))
    error_message = "Traffic Manager monitor path must start with /."
  }
}

variable "traffic_manager_monitor_interval" {
  description = "Traffic Manager monitor interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([10, 30], var.traffic_manager_monitor_interval)
    error_message = "Traffic Manager monitor interval must be either 10 or 30 seconds."
  }
}

variable "traffic_manager_monitor_timeout" {
  description = "Traffic Manager monitor timeout in seconds"
  type        = number
  default     = 10
  
  validation {
    condition     = var.traffic_manager_monitor_timeout >= 5 && var.traffic_manager_monitor_timeout <= 10
    error_message = "Traffic Manager monitor timeout must be between 5 and 10 seconds."
  }
}

variable "traffic_manager_monitor_tolerated_failures" {
  description = "Traffic Manager monitor tolerated number of failures"
  type        = number
  default     = 3
  
  validation {
    condition     = var.traffic_manager_monitor_tolerated_failures >= 0 && var.traffic_manager_monitor_tolerated_failures <= 9
    error_message = "Traffic Manager monitor tolerated failures must be between 0 and 9."
  }
}

# Endpoint Configuration
variable "endpoint_priorities" {
  description = "Priority values for Traffic Manager endpoints"
  type = object({
    primary   = number
    secondary = number
    tertiary  = number
  })
  default = {
    primary   = 1
    secondary = 2
    tertiary  = 3
  }
  
  validation {
    condition = alltrue([
      var.endpoint_priorities.primary >= 1 && var.endpoint_priorities.primary <= 1000,
      var.endpoint_priorities.secondary >= 1 && var.endpoint_priorities.secondary <= 1000,
      var.endpoint_priorities.tertiary >= 1 && var.endpoint_priorities.tertiary <= 1000
    ])
    error_message = "All endpoint priorities must be between 1 and 1000."
  }
}

variable "endpoint_weights" {
  description = "Weight values for Traffic Manager endpoints"
  type = object({
    primary   = number
    secondary = number
    tertiary  = number
  })
  default = {
    primary   = 100
    secondary = 100
    tertiary  = 100
  }
  
  validation {
    condition = alltrue([
      var.endpoint_weights.primary >= 1 && var.endpoint_weights.primary <= 1000,
      var.endpoint_weights.secondary >= 1 && var.endpoint_weights.secondary <= 1000,
      var.endpoint_weights.tertiary >= 1 && var.endpoint_weights.tertiary <= 1000
    ])
    error_message = "All endpoint weights must be between 1 and 1000."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and diagnostics"
  type        = bool
  default     = true
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of the supported values."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Security Configuration
variable "enable_ssh_key_authentication" {
  description = "Enable SSH key authentication for VMSS instances"
  type        = bool
  default     = true
}

variable "disable_password_authentication" {
  description = "Disable password authentication for VMSS instances"
  type        = bool
  default     = true
}

variable "enable_automatic_os_upgrade" {
  description = "Enable automatic OS upgrade for VMSS instances"
  type        = bool
  default     = true
}

variable "enable_health_probe" {
  description = "Enable health probe for VMSS instances"
  type        = bool
  default     = true
}