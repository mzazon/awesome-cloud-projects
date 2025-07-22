# Core configuration variables
variable "resource_group_name" {
  description = "Name of the resource group for quantum manufacturing resources"
  type        = string
  default     = "rg-quantum-manufacturing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "India South"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports quantum and ML services."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "quantum-manufacturing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Azure Machine Learning configuration
variable "ml_workspace_name" {
  description = "Name for Azure Machine Learning workspace"
  type        = string
  default     = "ws-quantum-ml"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.ml_workspace_name))
    error_message = "ML workspace name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "ml_compute_cluster_name" {
  description = "Name for ML compute cluster"
  type        = string
  default     = "quantum-ml-cluster"
}

variable "ml_compute_instance_size" {
  description = "VM size for ML compute instances"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS3_v2", "Standard_DS4_v2", "Standard_DS5_v2",
      "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_F4s_v2", "Standard_F8s_v2", "Standard_F16s_v2"
    ], var.ml_compute_instance_size)
    error_message = "ML compute instance size must be a valid Azure VM size suitable for ML workloads."
  }
}

variable "ml_compute_max_instances" {
  description = "Maximum number of instances for ML compute cluster"
  type        = number
  default     = 4
  
  validation {
    condition     = var.ml_compute_max_instances >= 1 && var.ml_compute_max_instances <= 100
    error_message = "ML compute max instances must be between 1 and 100."
  }
}

# Azure Quantum configuration
variable "quantum_workspace_name" {
  description = "Name for Azure Quantum workspace"
  type        = string
  default     = "qw-manufacturing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.quantum_workspace_name))
    error_message = "Quantum workspace name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# IoT Hub configuration
variable "iot_hub_name" {
  description = "Name for IoT Hub"
  type        = string
  default     = "iothub-manufacturing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.iot_hub_name))
    error_message = "IoT Hub name must contain only alphanumeric characters and hyphens."
  }
}

variable "iot_hub_sku" {
  description = "SKU for IoT Hub"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, S1, S2, S3."
  }
}

variable "iot_hub_capacity" {
  description = "Number of IoT Hub units"
  type        = number
  default     = 2
  
  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 32
    error_message = "IoT Hub partition count must be between 2 and 32."
  }
}

# Storage configuration
variable "storage_account_name" {
  description = "Name for storage account (will be made unique with random suffix)"
  type        = string
  default     = "stquantum"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.storage_account_name))
    error_message = "Storage account name must contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Stream Analytics configuration
variable "stream_analytics_job_name" {
  description = "Name for Stream Analytics job"
  type        = string
  default     = "sa-quality-control"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.stream_analytics_job_name))
    error_message = "Stream Analytics job name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 3
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Stream Analytics streaming units must be between 1 and 120."
  }
}

# Cosmos DB configuration
variable "cosmos_account_name" {
  description = "Name for Cosmos DB account"
  type        = string
  default     = "cosmos-quality-dashboard"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cosmos_account_name))
    error_message = "Cosmos DB account name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmos_throughput" {
  description = "Throughput for Cosmos DB container"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1000000."
  }
}

# Function App configuration
variable "function_app_name" {
  description = "Name for Function App"
  type        = string
  default     = "func-quality-dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.function_app_name))
    error_message = "Function App name must contain only alphanumeric characters and hyphens."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["dotnet", "java", "node", "python", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, java, node, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.9"
}

# Application Insights configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

# Key Vault configuration
variable "key_vault_name" {
  description = "Name for Key Vault (will be made unique with random suffix)"
  type        = string
  default     = "kv-quantum"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.key_vault_name))
    error_message = "Key Vault name must contain only alphanumeric characters and hyphens."
  }
}

# Resource tagging
variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Purpose     = "quantum-manufacturing"
    Environment = "demo"
    Workload    = "quality-control"
    CostCenter  = "manufacturing"
  }
}

# Enable/disable specific components
variable "enable_quantum_workspace" {
  description = "Enable Azure Quantum workspace deployment"
  type        = bool
  default     = true
}

variable "enable_stream_analytics" {
  description = "Enable Stream Analytics job deployment"
  type        = bool
  default     = true
}

variable "enable_cosmos_db" {
  description = "Enable Cosmos DB deployment"
  type        = bool
  default     = true
}

variable "enable_function_app" {
  description = "Enable Function App deployment"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and logging components"
  type        = bool
  default     = true
}