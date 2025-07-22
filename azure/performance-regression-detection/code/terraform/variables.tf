# Variables for Azure Performance Regression Detection Infrastructure

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-perftest"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "perftest"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters."
  }
}

# Load Testing Configuration
variable "load_test_name" {
  description = "Name of the Azure Load Testing resource"
  type        = string
  default     = "lt-perftest"
  
  validation {
    condition     = length(var.load_test_name) >= 1 && length(var.load_test_name) <= 50
    error_message = "Load test name must be between 1 and 50 characters."
  }
}

variable "load_test_description" {
  description = "Description for the Azure Load Testing resource"
  type        = string
  default     = "Automated performance regression detection for CI/CD pipelines"
}

# Log Analytics Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-perftest"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, PerNode, PerGB2018, Standalone."
  }
}

# Container Registry Configuration
variable "container_registry_name" {
  description = "Name of the Azure Container Registry"
  type        = string
  default     = "acrperftest"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.container_registry_name))
    error_message = "Container Registry name must contain only alphanumeric characters."
  }
}

variable "container_registry_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be one of: Basic, Standard, Premium."
  }
}

# Container Apps Configuration
variable "container_app_environment_name" {
  description = "Name of the Container Apps Environment"
  type        = string
  default     = "cae-perftest"
  
  validation {
    condition     = length(var.container_app_environment_name) >= 1 && length(var.container_app_environment_name) <= 60
    error_message = "Container Apps Environment name must be between 1 and 60 characters."
  }
}

variable "container_app_name" {
  description = "Name of the Container App"
  type        = string
  default     = "ca-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.container_app_name))
    error_message = "Container App name must contain only alphanumeric characters and hyphens."
  }
}

variable "container_app_image" {
  description = "Container image for the demo application"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "container_app_cpu" {
  description = "CPU allocation for the container app"
  type        = string
  default     = "0.5"
  
  validation {
    condition     = contains(["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "1.75", "2.0"], var.container_app_cpu)
    error_message = "Container App CPU must be one of: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0."
  }
}

variable "container_app_memory" {
  description = "Memory allocation for the container app"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = contains(["0.5Gi", "1.0Gi", "1.5Gi", "2.0Gi", "2.5Gi", "3.0Gi", "3.5Gi", "4.0Gi"], var.container_app_memory)
    error_message = "Container App memory must be one of: 0.5Gi, 1.0Gi, 1.5Gi, 2.0Gi, 2.5Gi, 3.0Gi, 3.5Gi, 4.0Gi."
  }
}

variable "container_app_min_replicas" {
  description = "Minimum number of replicas for the container app"
  type        = number
  default     = 1
  
  validation {
    condition     = var.container_app_min_replicas >= 0 && var.container_app_min_replicas <= 25
    error_message = "Container App min replicas must be between 0 and 25."
  }
}

variable "container_app_max_replicas" {
  description = "Maximum number of replicas for the container app"
  type        = number
  default     = 5
  
  validation {
    condition     = var.container_app_max_replicas >= 1 && var.container_app_max_replicas <= 25
    error_message = "Container App max replicas must be between 1 and 25."
  }
}

variable "container_app_target_port" {
  description = "Target port for the container app"
  type        = number
  default     = 80
  
  validation {
    condition     = var.container_app_target_port >= 1 && var.container_app_target_port <= 65535
    error_message = "Container App target port must be between 1 and 65535."
  }
}

# Application Insights Configuration
variable "application_insights_name" {
  description = "Name of the Application Insights resource"
  type        = string
  default     = "ai-perftest"
  
  validation {
    condition     = length(var.application_insights_name) >= 1 && length(var.application_insights_name) <= 260
    error_message = "Application Insights name must be between 1 and 260 characters."
  }
}

variable "application_insights_type" {
  description = "Type of Application Insights resource"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for performance regression detection"
  type        = bool
  default     = true
}

variable "response_time_threshold_ms" {
  description = "Response time threshold in milliseconds for alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.response_time_threshold_ms >= 100 && var.response_time_threshold_ms <= 10000
    error_message = "Response time threshold must be between 100 and 10000 milliseconds."
  }
}

variable "error_rate_threshold_percent" {
  description = "Error rate threshold in percentage for alerts"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_rate_threshold_percent >= 0 && var.error_rate_threshold_percent <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}

variable "alert_evaluation_frequency" {
  description = "How often to evaluate the alert rule (in minutes)"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_window_size" {
  description = "The period of time (in minutes) that is used to monitor alert activity"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60, 360, 720, 1440], var.alert_window_size)
    error_message = "Alert window size must be one of: 1, 5, 10, 15, 30, 60, 360, 720, 1440 minutes."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "performance-testing"
    Purpose     = "regression-detection"
    ManagedBy   = "terraform"
  }
}

# Advanced Configuration
variable "create_sample_load_test" {
  description = "Whether to create a sample load test configuration"
  type        = bool
  default     = true
}

variable "create_performance_workbook" {
  description = "Whether to create a performance monitoring workbook"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable Container Insights for the Container Apps environment"
  type        = bool
  default     = true
}