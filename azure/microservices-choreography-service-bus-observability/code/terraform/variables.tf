# Variable Definitions for Microservices Choreography Infrastructure
# This file defines all input variables that can be customized for the deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create"
  type        = string
  default     = "rg-microservices-choreography"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for all resources (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "project_name" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "choreography"
  
  validation {
    condition     = length(var.project_name) >= 2 && length(var.project_name) <= 20
    error_message = "Project name must be between 2 and 20 characters."
  }
}

variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "service_bus_capacity" {
  description = "Messaging units for Service Bus Premium (1, 2, 4, 8, 16)"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 4, 8, 16], var.service_bus_capacity)
    error_message = "Service Bus capacity must be 1, 2, 4, 8, or 16 messaging units."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid option."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain data in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "container_apps_cpu" {
  description = "CPU allocation for Container Apps (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0)"
  type        = number
  default     = 0.25
  
  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], var.container_apps_cpu)
    error_message = "Container Apps CPU must be a valid increment."
  }
}

variable "container_apps_memory" {
  description = "Memory allocation for Container Apps in Gi (0.5, 1.0, 1.5, 2.0, 3.0, 4.0)"
  type        = string
  default     = "0.5Gi"
  
  validation {
    condition     = contains(["0.5Gi", "1.0Gi", "1.5Gi", "2.0Gi", "3.0Gi", "4.0Gi"], var.container_apps_memory)
    error_message = "Container Apps memory must be a valid value."
  }
}

variable "container_apps_min_replicas" {
  description = "Minimum number of replicas for Container Apps"
  type        = number
  default     = 1
  
  validation {
    condition     = var.container_apps_min_replicas >= 0 && var.container_apps_min_replicas <= 30
    error_message = "Minimum replicas must be between 0 and 30."
  }
}

variable "container_apps_max_replicas" {
  description = "Maximum number of replicas for Container Apps"
  type        = number
  default     = 10
  
  validation {
    condition     = var.container_apps_max_replicas >= 1 && var.container_apps_max_replicas <= 30
    error_message = "Maximum replicas must be between 1 and 30."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for Azure Functions (node, dotnet, python, java)"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be node, dotnet, python, or java."
  }
}

variable "function_app_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_app_version)
    error_message = "Function App version must be ~3 or ~4."
  }
}

variable "enable_zone_redundancy" {
  description = "Enable zone redundancy for supported resources"
  type        = bool
  default     = false
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

variable "custom_tags" {
  description = "Additional custom tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.custom_tags) <= 15
    error_message = "Maximum of 15 custom tags allowed."
  }
}

variable "service_bus_topics" {
  description = "Configuration for Service Bus topics"
  type = map(object({
    max_message_size_in_kilobytes = number
    enable_partitioning          = bool
    requires_duplicate_detection = bool
    default_message_ttl          = string
    auto_delete_on_idle          = string
    enable_batched_operations    = bool
    support_ordering            = bool
  }))
  
  default = {
    "order-events" = {
      max_message_size_in_kilobytes = 1024
      enable_partitioning          = false
      requires_duplicate_detection = false
      default_message_ttl          = "P14D"
      auto_delete_on_idle          = "P10675199DT2H48M5.4775807S"
      enable_batched_operations    = true
      support_ordering            = false
    }
    "payment-events" = {
      max_message_size_in_kilobytes = 1024
      enable_partitioning          = false
      requires_duplicate_detection = false
      default_message_ttl          = "P14D"
      auto_delete_on_idle          = "P10675199DT2H48M5.4775807S"
      enable_batched_operations    = true
      support_ordering            = false
    }
    "inventory-events" = {
      max_message_size_in_kilobytes = 1024
      enable_partitioning          = false
      requires_duplicate_detection = false
      default_message_ttl          = "P14D"
      auto_delete_on_idle          = "P10675199DT2H48M5.4775807S"
      enable_batched_operations    = true
      support_ordering            = false
    }
    "shipping-events" = {
      max_message_size_in_kilobytes = 1024
      enable_partitioning          = false
      requires_duplicate_detection = false
      default_message_ttl          = "P14D"
      auto_delete_on_idle          = "P10675199DT2H48M5.4775807S"
      enable_batched_operations    = true
      support_ordering            = false
    }
  }
}

variable "service_bus_subscriptions" {
  description = "Configuration for Service Bus topic subscriptions"
  type = map(object({
    topic_name                    = string
    max_delivery_count           = number
    lock_duration               = string
    requires_session           = bool
    default_message_ttl         = string
    auto_delete_on_idle         = string
    enable_batched_operations   = bool
    dead_lettering_on_message_expiration = bool
    dead_lettering_on_filter_evaluation_error = bool
  }))
  
  default = {
    "payment-service-sub" = {
      topic_name                    = "order-events"
      max_delivery_count           = 10
      lock_duration               = "PT1M"
      requires_session           = false
      default_message_ttl         = "P14D"
      auto_delete_on_idle         = "P10675199DT2H48M5.4775807S"
      enable_batched_operations   = true
      dead_lettering_on_message_expiration = true
      dead_lettering_on_filter_evaluation_error = true
    }
    "inventory-service-sub" = {
      topic_name                    = "order-events"
      max_delivery_count           = 10
      lock_duration               = "PT1M"
      requires_session           = false
      default_message_ttl         = "P14D"
      auto_delete_on_idle         = "P10675199DT2H48M5.4775807S"
      enable_batched_operations   = true
      dead_lettering_on_message_expiration = true
      dead_lettering_on_filter_evaluation_error = true
    }
    "shipping-service-sub" = {
      topic_name                    = "payment-events"
      max_delivery_count           = 10
      lock_duration               = "PT1M"
      requires_session           = false
      default_message_ttl         = "P14D"
      auto_delete_on_idle         = "P10675199DT2H48M5.4775807S"
      enable_batched_operations   = true
      dead_lettering_on_message_expiration = true
      dead_lettering_on_filter_evaluation_error = true
    }
    "high-priority-orders" = {
      topic_name                    = "order-events"
      max_delivery_count           = 3
      lock_duration               = "PT30S"
      requires_session           = false
      default_message_ttl         = "P7D"
      auto_delete_on_idle         = "P10675199DT2H48M5.4775807S"
      enable_batched_operations   = true
      dead_lettering_on_message_expiration = true
      dead_lettering_on_filter_evaluation_error = true
    }
  }
}