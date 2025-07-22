# Variables for FHIR-compliant healthcare API orchestration infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for healthcare resources"
  type        = string
  default     = "rg-healthcare-fhir"
}

variable "location" {
  description = "Azure region for healthcare resources"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Switzerland North", "Germany West Central",
      "Norway East", "UAE North", "South Africa North", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "Central India", "South India"
    ], var.location)
    error_message = "The location must be a valid Azure region where Healthcare APIs are available."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "organization_name" {
  description = "Name of the healthcare organization"
  type        = string
  default     = "Healthcare Organization"
}

variable "admin_email" {
  description = "Administrator email for API Management"
  type        = string
  default     = "admin@healthcare.org"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "healthcare-fhir"
    Environment = "dev"
    Compliance  = "hipaa"
    Workload    = "fhir-api"
  }
}

# Healthcare workspace configuration
variable "health_workspace_name" {
  description = "Name of the Azure Health Data Services workspace"
  type        = string
  default     = "hw-healthcare"
}

variable "fhir_service_name" {
  description = "Name of the FHIR service"
  type        = string
  default     = "fhir-service"
}

variable "fhir_version" {
  description = "FHIR version to use"
  type        = string
  default     = "fhir-R4"
  validation {
    condition     = contains(["fhir-R4"], var.fhir_version)
    error_message = "FHIR version must be fhir-R4."
  }
}

variable "enable_smart_proxy" {
  description = "Enable SMART on FHIR proxy"
  type        = bool
  default     = true
}

# Container Apps configuration
variable "container_environment_name" {
  description = "Name of the Container Apps environment"
  type        = string
  default     = "cae-healthcare"
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "log-healthcare"
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

# Container Apps scaling configuration
variable "patient_service_config" {
  description = "Configuration for patient service container app"
  type = object({
    cpu               = number
    memory            = string
    min_replicas      = number
    max_replicas      = number
    target_port       = number
    image            = string
    ingress_external = bool
  })
  default = {
    cpu               = 0.5
    memory            = "1.0Gi"
    min_replicas      = 1
    max_replicas      = 10
    target_port       = 80
    image            = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    ingress_external = true
  }
}

variable "provider_notification_config" {
  description = "Configuration for provider notification service"
  type = object({
    cpu               = number
    memory            = string
    min_replicas      = number
    max_replicas      = number
    target_port       = number
    image            = string
    ingress_external = bool
  })
  default = {
    cpu               = 0.25
    memory            = "0.5Gi"
    min_replicas      = 1
    max_replicas      = 5
    target_port       = 80
    image            = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    ingress_external = true
  }
}

variable "workflow_orchestration_config" {
  description = "Configuration for workflow orchestration service"
  type = object({
    cpu               = number
    memory            = string
    min_replicas      = number
    max_replicas      = number
    target_port       = number
    image            = string
    ingress_external = bool
  })
  default = {
    cpu               = 1.0
    memory            = "2.0Gi"
    min_replicas      = 2
    max_replicas      = 8
    target_port       = 80
    image            = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    ingress_external = true
  }
}

# Communication Services configuration
variable "communication_service_name" {
  description = "Name of the Communication Services resource"
  type        = string
  default     = "comm-healthcare"
}

variable "communication_data_location" {
  description = "Data location for Communication Services"
  type        = string
  default     = "United States"
  validation {
    condition = contains([
      "United States", "Europe", "Asia Pacific", "Australia", "United Kingdom"
    ], var.communication_data_location)
    error_message = "Communication data location must be a valid region."
  }
}

# API Management configuration
variable "api_management_name" {
  description = "Name of the API Management instance"
  type        = string
  default     = "apim-healthcare"
}

variable "api_management_sku" {
  description = "SKU for API Management"
  type        = string
  default     = "Developer"
  validation {
    condition = contains([
      "Developer", "Basic", "Standard", "Premium", "Consumption"
    ], var.api_management_sku)
    error_message = "API Management SKU must be one of: Developer, Basic, Standard, Premium, Consumption."
  }
}

variable "api_management_capacity" {
  description = "Capacity for API Management (scale units)"
  type        = number
  default     = 1
  validation {
    condition     = var.api_management_capacity >= 1 && var.api_management_capacity <= 10
    error_message = "API Management capacity must be between 1 and 10."
  }
}

# Security and compliance configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 365
    error_message = "Log retention must be between 30 and 365 days."
  }
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the API Management"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Application Insights configuration
variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = "ai-healthcare"
}

variable "application_insights_type" {
  description = "Type of Application Insights"
  type        = string
  default     = "web"
  validation {
    condition     = contains(["web", "java", "other"], var.application_insights_type)
    error_message = "Application Insights type must be one of: web, java, other."
  }
}

# Random suffix for unique naming
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 3 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 3 and 10."
  }
}