# Variables for the Azure Service Fabric and Application Insights monitoring solution

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-microservices-monitoring"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "microservices-monitoring"
    environment = "demo"
    project     = "service-fabric-monitoring"
  }
}

# Service Fabric cluster configuration
variable "sf_cluster_name" {
  description = "Name of the Service Fabric cluster"
  type        = string
  default     = "sf-cluster"
}

variable "sf_cluster_sku" {
  description = "SKU for the Service Fabric managed cluster"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.sf_cluster_sku)
    error_message = "Service Fabric cluster SKU must be either 'Basic' or 'Standard'."
  }
}

variable "sf_admin_username" {
  description = "Admin username for Service Fabric cluster"
  type        = string
  default     = "azureuser"
}

variable "sf_admin_password" {
  description = "Admin password for Service Fabric cluster"
  type        = string
  sensitive   = true
  default     = "ComplexPassword123!"
  
  validation {
    condition     = length(var.sf_admin_password) >= 12
    error_message = "Password must be at least 12 characters long."
  }
}

variable "sf_client_connection_port" {
  description = "Client connection port for Service Fabric cluster"
  type        = number
  default     = 19000
}

variable "sf_http_gateway_port" {
  description = "HTTP gateway port for Service Fabric cluster"
  type        = number
  default     = 19080
}

# Application Insights configuration
variable "app_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "ai-monitoring"
}

variable "app_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition = contains(["web", "other"], var.app_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Log Analytics workspace configuration
variable "log_analytics_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "la-workspace"
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Event Hub configuration
variable "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  type        = string
  default     = "eh-namespace"
}

variable "event_hub_namespace_sku" {
  description = "SKU for the Event Hub namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Basic", "Standard", "Premium"], var.event_hub_namespace_sku)
    error_message = "Event Hub namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "event_hub_namespace_capacity" {
  description = "Capacity (throughput units) for Event Hub namespace"
  type        = number
  default     = 1
  
  validation {
    condition     = var.event_hub_namespace_capacity >= 1 && var.event_hub_namespace_capacity <= 20
    error_message = "Event Hub namespace capacity must be between 1 and 20 throughput units."
  }
}

variable "event_hub_auto_inflate_enabled" {
  description = "Enable auto-inflate for Event Hub namespace"
  type        = bool
  default     = true
}

variable "event_hub_maximum_throughput_units" {
  description = "Maximum throughput units for auto-inflate"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_hub_maximum_throughput_units >= 1 && var.event_hub_maximum_throughput_units <= 20
    error_message = "Maximum throughput units must be between 1 and 20."
  }
}

variable "event_hub_name" {
  description = "Name of the Event Hub"
  type        = string
  default     = "service-events"
}

variable "event_hub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.event_hub_partition_count >= 1 && var.event_hub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "event_hub_message_retention" {
  description = "Message retention period in days for Event Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.event_hub_message_retention >= 1 && var.event_hub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Function App configuration
variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
  default     = "fn-eventprocessor"
}

variable "storage_account_name" {
  description = "Name of the storage account for Function App"
  type        = string
  default     = "st"
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_service_plan_name" {
  description = "Name of the service plan for Function App"
  type        = string
  default     = "sp-functions"
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition = contains(["dotnet", "java", "node", "python", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, java, node, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
}

variable "function_app_functions_version" {
  description = "Functions extension version"
  type        = string
  default     = "4"
  
  validation {
    condition = contains(["3", "4"], var.function_app_functions_version)
    error_message = "Functions version must be either '3' or '4'."
  }
}

# Monitoring and alerting configuration
variable "diagnostic_setting_name" {
  description = "Name of the diagnostic setting"
  type        = string
  default     = "sf-diagnostics"
}

variable "metric_alert_name" {
  description = "Name of the metric alert for cluster health"
  type        = string
  default     = "Service Fabric Cluster Health"
}

variable "query_alert_name" {
  description = "Name of the query alert for error rate"
  type        = string
  default     = "High Error Rate Alert"
}

variable "alert_evaluation_frequency" {
  description = "Frequency for alert evaluation"
  type        = string
  default     = "PT1M"
  
  validation {
    condition = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_window_size" {
  description = "Window size for alert evaluation"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT24H"], var.alert_window_size)
    error_message = "Alert window size must be a valid time duration."
  }
}

variable "alert_severity" {
  description = "Severity level for alerts"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 and 4."
  }
}

variable "error_threshold" {
  description = "Threshold for error rate alert"
  type        = number
  default     = 10
  
  validation {
    condition     = var.error_threshold > 0
    error_message = "Error threshold must be greater than 0."
  }
}

# Dashboard configuration
variable "dashboard_name" {
  description = "Name of the monitoring dashboard"
  type        = string
  default     = "Microservices Monitoring Dashboard"
}