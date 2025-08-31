# Input variables for the Simple Contact Form infrastructure
# These variables allow customization of the deployment while maintaining best practices

variable "resource_group_name" {
  description = "Name of the Azure Resource Group. If not provided, a unique name will be generated."
  type        = string
  default     = null

  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 &&
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where all resources will be deployed. Choose a region close to your users for optimal performance."
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "West Europe", "North Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "India Central", "Canada Central", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, test, prod). Used for resource organization and cost tracking."
  type        = string
  default     = "demo"

  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric characters only and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging. Used as a prefix for resource names."
  type        = string
  default     = "contact-form"

  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric characters and hyphens only, no more than 20 characters."
  }
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account. Standard is cost-effective for most workloads."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage replication type. LRS (Locally Redundant Storage) is cost-effective for non-critical data. Use GRS for higher durability."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_sku" {
  description = "SKU name for the App Service Plan. Y1 is the consumption plan (pay-per-execution), ideal for variable workloads."
  type        = string
  default     = "Y1"

  validation {
    condition = contains([
      "Y1",           # Consumption plan
      "EP1", "EP2", "EP3",  # Elastic Premium plans
      "P1", "P2", "P3"      # Premium plans
    ], var.function_app_sku)
    error_message = "Function app SKU must be one of: Y1 (Consumption), EP1/EP2/EP3 (Elastic Premium), or P1/P2/P3 (Premium)."
  }
}

variable "function_runtime" {
  description = "Runtime stack for the Function App. Node.js is used for JavaScript-based Azure Functions."
  type        = string
  default     = "node"

  validation {
    condition     = contains(["node", "dotnet", "java", "powershell", "python"], var.function_runtime)
    error_message = "Function runtime must be one of: node, dotnet, java, powershell, python."
  }
}

variable "function_runtime_version" {
  description = "Version of the Function runtime. Node.js 20 is the current LTS version with best performance and security."
  type        = string
  default     = "~20"

  validation {
    condition = var.function_runtime == "node" ? contains(["~18", "~20", "~22"], var.function_runtime_version) : (
      var.function_runtime == "dotnet" ? contains(["v6.0", "v8.0"], var.function_runtime_version) : (
        var.function_runtime == "python" ? contains(["3.9", "3.10", "3.11"], var.function_runtime_version) : true
      )
    )
    error_message = "Runtime version must be compatible with the selected runtime."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions runtime version. ~4 is the current stable version with latest features and security updates."
  type        = string
  default     = "~4"

  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring and logging. Recommended for production workloads."
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS requests. Use ['*'] for all origins (not recommended for production)."
  type        = list(string)
  default     = ["*"]
}

variable "contact_table_name" {
  description = "Name of the Azure Storage Table for storing contact form submissions."
  type        = string
  default     = "contacts"

  validation {
    condition = length(var.contact_table_name) >= 3 && length(var.contact_table_name) <= 63 && (
      can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.contact_table_name))
    )
    error_message = "Table name must be 3-63 characters, start with a letter, and contain only alphanumeric characters."
  }
}

variable "daily_memory_time_quota_gb" {
  description = "Daily memory time quota in GB-seconds for consumption plan Function Apps. 0 means no quota (unlimited)."
  type        = number
  default     = 0

  validation {
    condition     = var.daily_memory_time_quota_gb >= 0
    error_message = "Daily memory time quota must be zero or positive."
  }
}

variable "https_only" {
  description = "Require HTTPS for all Function App traffic. Recommended for security in production environments."
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version required for connections. 1.2 is recommended for security compliance."
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources for organization, cost tracking, and governance."
  type        = map(string)
  default = {
    Project     = "Contact Form"
    ManagedBy   = "Terraform"
    Purpose     = "Serverless contact form processing"
    CostCenter  = "Marketing"
  }
}

variable "enable_public_network_access" {
  description = "Allow public network access to the Function App. Set to false for private endpoints only."
  type        = bool
  default     = true
}