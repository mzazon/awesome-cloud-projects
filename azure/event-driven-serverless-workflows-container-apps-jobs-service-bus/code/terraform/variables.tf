# Core configuration variables
variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = "rg-container-jobs-demo"
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 64
    error_message = "Resource group name must be between 3 and 64 characters."
  }
}

variable "location" {
  description = "The Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Southeast Asia",
      "East Asia", "Japan East", "Japan West", "Korea Central",
      "Canada Central", "Canada East", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

# Container Apps Environment configuration
variable "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  type        = string
  default     = "env-container-jobs"
  
  validation {
    condition     = length(var.container_apps_environment_name) >= 2 && length(var.container_apps_environment_name) <= 32
    error_message = "Container Apps Environment name must be between 2 and 32 characters."
  }
}

variable "container_apps_job_name" {
  description = "Name of the Container Apps Job"
  type        = string
  default     = "message-processor-job"
  
  validation {
    condition     = length(var.container_apps_job_name) >= 2 && length(var.container_apps_job_name) <= 32
    error_message = "Container Apps Job name must be between 2 and 32 characters."
  }
}

# Service Bus configuration
variable "service_bus_namespace_name" {
  description = "Name of the Service Bus namespace (must be globally unique)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.service_bus_namespace_name == "" || (length(var.service_bus_namespace_name) >= 6 && length(var.service_bus_namespace_name) <= 50)
    error_message = "Service Bus namespace name must be between 6 and 50 characters."
  }
}

variable "service_bus_sku" {
  description = "SKU for the Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "queue_name" {
  description = "Name of the Service Bus queue"
  type        = string
  default     = "message-processing-queue"
  
  validation {
    condition     = length(var.queue_name) >= 1 && length(var.queue_name) <= 260
    error_message = "Queue name must be between 1 and 260 characters."
  }
}

variable "queue_max_delivery_count" {
  description = "Maximum number of delivery attempts for messages"
  type        = number
  default     = 5
  
  validation {
    condition     = var.queue_max_delivery_count >= 1 && var.queue_max_delivery_count <= 2000
    error_message = "Max delivery count must be between 1 and 2000."
  }
}

variable "queue_lock_duration" {
  description = "ISO 8601 duration for message lock"
  type        = string
  default     = "PT1M"
  
  validation {
    condition     = can(regex("^PT([0-9]+M|[0-9]+S)$", var.queue_lock_duration))
    error_message = "Lock duration must be in ISO 8601 format (e.g., PT1M for 1 minute)."
  }
}

# Container Registry configuration
variable "container_registry_name" {
  description = "Name of the Azure Container Registry (must be globally unique)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.container_registry_name == "" || (length(var.container_registry_name) >= 5 && length(var.container_registry_name) <= 50)
    error_message = "Container Registry name must be between 5 and 50 characters."
  }
}

variable "container_registry_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = true
}

# Container Apps Job configuration
variable "job_trigger_type" {
  description = "Trigger type for the Container Apps Job"
  type        = string
  default     = "Event"
  
  validation {
    condition     = contains(["Event", "Manual", "Schedule"], var.job_trigger_type)
    error_message = "Job trigger type must be Event, Manual, or Schedule."
  }
}

variable "job_replica_timeout" {
  description = "Maximum execution time in seconds for job replicas"
  type        = number
  default     = 1800
  
  validation {
    condition     = var.job_replica_timeout >= 60 && var.job_replica_timeout <= 1800
    error_message = "Replica timeout must be between 60 and 1800 seconds."
  }
}

variable "job_replica_retry_limit" {
  description = "Maximum number of retries for failed job replicas"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_replica_retry_limit >= 0 && var.job_replica_retry_limit <= 10
    error_message = "Replica retry limit must be between 0 and 10."
  }
}

variable "job_replica_completion_count" {
  description = "Number of replicas that must complete successfully"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_replica_completion_count >= 1 && var.job_replica_completion_count <= 100
    error_message = "Replica completion count must be between 1 and 100."
  }
}

variable "job_parallelism" {
  description = "Maximum number of job replicas that can run in parallel"
  type        = number
  default     = 5
  
  validation {
    condition     = var.job_parallelism >= 1 && var.job_parallelism <= 100
    error_message = "Job parallelism must be between 1 and 100."
  }
}

variable "job_min_executions" {
  description = "Minimum number of job executions"
  type        = number
  default     = 0
  
  validation {
    condition     = var.job_min_executions >= 0 && var.job_min_executions <= 1000
    error_message = "Minimum executions must be between 0 and 1000."
  }
}

variable "job_max_executions" {
  description = "Maximum number of job executions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.job_max_executions >= 1 && var.job_max_executions <= 1000
    error_message = "Maximum executions must be between 1 and 1000."
  }
}

variable "job_polling_interval" {
  description = "Polling interval in seconds for event triggers"
  type        = number
  default     = 30
  
  validation {
    condition     = var.job_polling_interval >= 10 && var.job_polling_interval <= 300
    error_message = "Polling interval must be between 10 and 300 seconds."
  }
}

variable "job_scale_rule_message_count" {
  description = "Number of messages that triggers scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_scale_rule_message_count >= 1 && var.job_scale_rule_message_count <= 1000
    error_message = "Scale rule message count must be between 1 and 1000."
  }
}

# Container configuration
variable "container_image_name" {
  description = "Name of the container image"
  type        = string
  default     = "message-processor:1.0"
}

variable "container_cpu" {
  description = "CPU allocation for container (in cores)"
  type        = string
  default     = "0.5"
  
  validation {
    condition     = contains(["0.25", "0.5", "0.75", "1.0", "1.25", "1.5", "1.75", "2.0"], var.container_cpu)
    error_message = "Container CPU must be one of: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0."
  }
}

variable "container_memory" {
  description = "Memory allocation for container"
  type        = string
  default     = "1Gi"
  
  validation {
    condition     = contains(["0.5Gi", "1Gi", "1.5Gi", "2Gi", "2.5Gi", "3Gi", "3.5Gi", "4Gi"], var.container_memory)
    error_message = "Container memory must be one of: 0.5Gi, 1Gi, 1.5Gi, 2Gi, 2.5Gi, 3Gi, 3.5Gi, 4Gi."
  }
}

# Monitoring and alerting configuration
variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for job failures"
  type        = bool
  default     = true
}

variable "alert_evaluation_frequency" {
  description = "Frequency for alert evaluation (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.alert_window_size)
    error_message = "Alert window size must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_severity" {
  description = "Severity level for alerts"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 (Critical) and 4 (Verbose)."
  }
}

# Tagging configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Demo"
    Environment = "Learning"
    Project     = "ContainerAppsJobs"
    CreatedBy   = "Terraform"
  }
}