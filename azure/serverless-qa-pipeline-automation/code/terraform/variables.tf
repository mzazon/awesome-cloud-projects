# Common variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "qa-pipeline"
}

# Container Apps Environment variables
variable "container_env_name" {
  description = "Name of the Container Apps Environment"
  type        = string
  default     = null
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = null
}

variable "log_analytics_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
}

# Storage Account variables
variable "storage_account_name" {
  description = "Name of the storage account"
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

# Load Testing variables
variable "load_test_name" {
  description = "Name of the Azure Load Testing resource"
  type        = string
  default     = null
}

# Container Apps Job variables
variable "unit_test_job_config" {
  description = "Configuration for unit test job"
  type = object({
    image               = string
    cpu                 = number
    memory              = string
    replica_timeout     = number
    replica_retry_limit = number
    parallelism         = number
  })
  default = {
    image               = "mcr.microsoft.com/dotnet/sdk:7.0"
    cpu                 = 1.0
    memory              = "2Gi"
    replica_timeout     = 1800
    replica_retry_limit = 3
    parallelism         = 3
  }
}

variable "integration_test_job_config" {
  description = "Configuration for integration test job"
  type = object({
    image               = string
    cpu                 = number
    memory              = string
    replica_timeout     = number
    replica_retry_limit = number
    parallelism         = number
  })
  default = {
    image               = "mcr.microsoft.com/dotnet/sdk:7.0"
    cpu                 = 1.5
    memory              = "3Gi"
    replica_timeout     = 3600
    replica_retry_limit = 2
    parallelism         = 2
  }
}

variable "performance_test_job_config" {
  description = "Configuration for performance test job"
  type = object({
    image               = string
    cpu                 = number
    memory              = string
    replica_timeout     = number
    replica_retry_limit = number
    parallelism         = number
  })
  default = {
    image               = "mcr.microsoft.com/azure-cli:latest"
    cpu                 = 0.5
    memory              = "1Gi"
    replica_timeout     = 7200
    replica_retry_limit = 1
    parallelism         = 1
  }
}

variable "security_test_job_config" {
  description = "Configuration for security test job"
  type = object({
    image               = string
    cpu                 = number
    memory              = string
    replica_timeout     = number
    replica_retry_limit = number
    parallelism         = number
  })
  default = {
    image               = "mcr.microsoft.com/dotnet/sdk:7.0"
    cpu                 = 1.0
    memory              = "2Gi"
    replica_timeout     = 2400
    replica_retry_limit = 2
    parallelism         = 1
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    purpose     = "qa-pipeline"
    environment = "demo"
    managed_by  = "terraform"
  }
}