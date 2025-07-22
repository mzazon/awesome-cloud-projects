# Variables for Azure Quantum-Enhanced Financial Risk Analytics Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for quantum finance analytics"
  type        = string
  default     = "rg-quantum-finance"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US 2", "West Europe", 
      "North Europe", "Southeast Asia", "Australia East"
    ], var.location)
    error_message = "Location must be in a region that supports Azure Quantum services."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "quantum-finance"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "sql_administrator_login" {
  description = "SQL administrator login for Synapse workspace"
  type        = string
  default     = "synapseadmin"
}

variable "sql_administrator_password" {
  description = "SQL administrator password for Synapse workspace"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.sql_administrator_password == null || (
      length(var.sql_administrator_password) >= 8 &&
      can(regex("[A-Z]", var.sql_administrator_password)) &&
      can(regex("[a-z]", var.sql_administrator_password)) &&
      can(regex("[0-9]", var.sql_administrator_password)) &&
      can(regex("[^A-Za-z0-9]", var.sql_administrator_password))
    )
    error_message = "Password must be at least 8 characters with uppercase, lowercase, number, and special character."
  }
}

variable "spark_pool_node_size" {
  description = "Node size for Synapse Spark pool"
  type        = string
  default     = "Medium"
  
  validation {
    condition     = contains(["Small", "Medium", "Large", "XLarge", "XXLarge"], var.spark_pool_node_size)
    error_message = "Spark pool node size must be Small, Medium, Large, XLarge, or XXLarge."
  }
}

variable "spark_pool_min_nodes" {
  description = "Minimum number of nodes for Synapse Spark pool"
  type        = number
  default     = 3
  
  validation {
    condition     = var.spark_pool_min_nodes >= 3
    error_message = "Minimum nodes must be at least 3 for Spark pool."
  }
}

variable "spark_pool_max_nodes" {
  description = "Maximum number of nodes for Synapse Spark pool"
  type        = number
  default     = 10
  
  validation {
    condition     = var.spark_pool_max_nodes >= var.spark_pool_min_nodes && var.spark_pool_max_nodes <= 100
    error_message = "Maximum nodes must be greater than minimum nodes and less than 100."
  }
}

variable "ml_compute_tier" {
  description = "Compute tier for Azure Machine Learning"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.ml_compute_tier)
    error_message = "ML compute tier must be Basic, Standard, or Premium."
  }
}

variable "ml_compute_min_instances" {
  description = "Minimum compute instances for ML cluster"
  type        = number
  default     = 0
  
  validation {
    condition     = var.ml_compute_min_instances >= 0 && var.ml_compute_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "ml_compute_max_instances" {
  description = "Maximum compute instances for ML cluster"
  type        = number
  default     = 4
  
  validation {
    condition     = var.ml_compute_max_instances >= 1 && var.ml_compute_max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
}

variable "storage_replication_type" {
  description = "Storage replication type for Data Lake"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS"], var.storage_replication_type)
    error_message = "Storage replication must be LRS, ZRS, GRS, or RAGRS."
  }
}

variable "enable_quantum_providers" {
  description = "List of quantum providers to enable"
  type        = list(string)
  default     = ["Microsoft"]
  
  validation {
    condition = alltrue([
      for provider in var.enable_quantum_providers : 
      contains(["Microsoft", "IonQ", "Quantinuum", "Rigetti"], provider)
    ])
    error_message = "Quantum providers must be from: Microsoft, IonQ, Quantinuum, Rigetti."
  }
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights and Log Analytics"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default = {
    Purpose     = "Quantum Financial Analytics"
    Technology  = "Azure Quantum + Synapse"
    CostCenter  = "Analytics"
  }
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : 
      can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}