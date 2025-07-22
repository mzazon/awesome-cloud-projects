# Variable definitions for Azure Document Verification System

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated with prefix and environment"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "docverify"
  
  validation {
    condition     = length(var.project_name) >= 2 && length(var.project_name) <= 20
    error_message = "Project name must be between 2 and 20 characters."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DocumentVerification"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Cognitive Services Configuration
variable "document_intelligence_sku" {
  description = "SKU for Azure Document Intelligence service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be either F0 (free) or S0 (standard)."
  }
}

variable "computer_vision_sku" {
  description = "SKU for Azure Computer Vision service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S1"], var.computer_vision_sku)
    error_message = "Computer Vision SKU must be either F0 (free) or S1 (standard)."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be one of: Y1 (consumption), EP1, EP2, EP3 (premium)."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.11"
}

# Cosmos DB Configuration
variable "cosmos_db_offer_type" {
  description = "Cosmos DB offer type"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = var.cosmos_db_offer_type == "Standard"
    error_message = "Cosmos DB offer type must be Standard."
  }
}

variable "cosmos_db_kind" {
  description = "Cosmos DB kind"
  type        = string
  default     = "GlobalDocumentDB"
  
  validation {
    condition     = contains(["GlobalDocumentDB", "MongoDB", "Parse"], var.cosmos_db_kind)
    error_message = "Cosmos DB kind must be one of: GlobalDocumentDB, MongoDB, Parse."
  }
}

variable "cosmos_db_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"], var.cosmos_db_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmos_db_throughput" {
  description = "Cosmos DB container throughput (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_db_throughput >= 400 && var.cosmos_db_throughput <= 100000
    error_message = "Cosmos DB throughput must be between 400 and 100000 RU/s."
  }
}

# Logic App Configuration
variable "logic_app_enabled" {
  description = "Whether to deploy Logic App for workflow orchestration"
  type        = bool
  default     = true
}

# API Management Configuration
variable "api_management_enabled" {
  description = "Whether to deploy API Management for secure API access"
  type        = bool
  default     = true
}

variable "api_management_sku" {
  description = "SKU for API Management service"
  type        = string
  default     = "Developer"
  
  validation {
    condition     = contains(["Developer", "Basic", "Standard", "Premium"], var.api_management_sku)
    error_message = "API Management SKU must be one of: Developer, Basic, Standard, Premium."
  }
}

variable "api_management_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "Document Verification System"
}

variable "api_management_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.api_management_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Whether to enable private endpoints for secure connectivity"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the resources"
  type        = list(string)
  default     = []
}

# Monitoring Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}

# Backup Configuration
variable "enable_backup" {
  description = "Whether to enable backup for critical resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 7 and 35."
  }
}

# Scaling Configuration
variable "autoscale_enabled" {
  description = "Whether to enable autoscaling for Function App"
  type        = bool
  default     = true
}

variable "max_instances" {
  description = "Maximum number of instances for Function App scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 100
    error_message = "Maximum instances must be between 1 and 100."
  }
}