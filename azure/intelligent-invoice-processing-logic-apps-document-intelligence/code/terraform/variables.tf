# Variables for Azure Invoice Processing Infrastructure

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-invoice-processing"
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
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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
  default     = "invoice-processing"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for Storage Account"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for Storage Account"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "document_intelligence_sku" {
  description = "SKU for Azure AI Document Intelligence service"
  type        = string
  default     = "S0"
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be F0 (free) or S0 (standard)."
  }
}

variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "function_app_sku" {
  description = "SKU for Function App hosting plan"
  type        = string
  default     = "Y1"
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_sku)
    error_message = "Function App SKU must be Y1 (consumption) or EP1-EP3 (elastic premium)."
  }
}

variable "invoice_approval_threshold" {
  description = "Dollar amount threshold for invoice approval workflow"
  type        = number
  default     = 1000
  validation {
    condition     = var.invoice_approval_threshold > 0
    error_message = "Invoice approval threshold must be greater than 0."
  }
}

variable "approver_email" {
  description = "Email address for invoice approval notifications"
  type        = string
  default     = "finance-approver@company.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.approver_email))
    error_message = "Approver email must be a valid email address."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for storage account"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain processed invoices"
  type        = number
  default     = 2555  # 7 years for compliance
  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 3650
    error_message = "Retention days must be between 30 and 3650 (10 years)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Invoice Processing Automation"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "Document Intelligence and Workflow Automation"
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access storage account"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure connectivity"
  type        = bool
  default     = false
}