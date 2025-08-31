# Variable definitions for Azure basic file storage Terraform configuration
# These variables provide customization options for the storage solution
# while maintaining secure defaults and proper validation

# =============================================================================
# CORE CONFIGURATION VARIABLES
# =============================================================================

variable "resource_group_name" {
  description = "The name of the Azure resource group where all storage resources will be created. If not provided, a unique name will be generated."
  type        = string
  default     = null

  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 &&
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._()-]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed. Choose a region close to your users for optimal performance."
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast",
      "Southeast Asia", "East Asia",
      "Japan East", "Japan West",
      "Korea Central", "India Central"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "storage_account_name" {
  description = "The name of the Azure storage account. Must be globally unique across all Azure storage accounts. If not provided, a unique name will be generated."
  type        = string
  default     = null

  validation {
    condition = var.storage_account_name == null || (
      length(var.storage_account_name) >= 3 &&
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

# =============================================================================
# STORAGE CONFIGURATION VARIABLES
# =============================================================================

variable "account_tier" {
  description = "The performance tier of the storage account. Standard provides cost-effective storage, Premium offers higher performance with SSD backing."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  description = "The replication strategy for the storage account. LRS is most cost-effective, while GRS provides geo-redundancy for disaster recovery."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "The default access tier for blob storage. Hot tier is optimized for frequently accessed data, Cool for infrequently accessed data."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "Access tier must be either 'Hot' or 'Cool'."
  }
}

variable "min_tls_version" {
  description = "The minimum TLS version required for storage account access. TLS1_2 is recommended for security compliance."
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "allow_blob_public_access" {
  description = "Whether to allow public access to blobs in the storage account. Set to false for enhanced security."
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Whether to enable shared access key authentication. When disabled, only Azure AD authentication is allowed."
  type        = bool
  default     = true
}

variable "https_traffic_only_enabled" {
  description = "Whether to enforce HTTPS traffic only. Should be true for production environments to ensure secure data transfer."
  type        = bool
  default     = true
}

# =============================================================================
# CONTAINER CONFIGURATION VARIABLES
# =============================================================================

variable "blob_containers" {
  description = "Map of blob containers to create with their access levels. Container names must be lowercase and follow DNS naming rules."
  type = map(object({
    container_access_type = string
    metadata             = map(string)
  }))
  default = {
    documents = {
      container_access_type = "private"
      metadata = {
        purpose     = "Document storage"
        environment = "demo"
      }
    }
    images = {
      container_access_type = "private"
      metadata = {
        purpose     = "Image storage"
        environment = "demo"
      }
    }
    backups = {
      container_access_type = "private"
      metadata = {
        purpose     = "Backup storage"
        environment = "demo"
      }
    }
  }

  validation {
    condition = alltrue([
      for name, config in var.blob_containers :
      length(name) >= 3 && length(name) <= 63 &&
      can(regex("^[a-z0-9-]+$", name)) &&
      !can(regex("^-", name)) &&
      !can(regex("-$", name)) &&
      !can(regex("--", name))
    ])
    error_message = "Container names must be 3-63 characters, lowercase, and contain only letters, numbers, and hyphens (not at start/end or consecutive)."
  }

  validation {
    condition = alltrue([
      for name, config in var.blob_containers :
      contains(["private", "blob", "container"], config.container_access_type)
    ])
    error_message = "Container access type must be 'private', 'blob', or 'container'."
  }
}

# =============================================================================
# RBAC CONFIGURATION VARIABLES
# =============================================================================

variable "enable_rbac_for_current_user" {
  description = "Whether to automatically assign Storage Blob Data Contributor role to the current user/service principal."
  type        = bool
  default     = true
}

variable "additional_rbac_assignments" {
  description = "Additional RBAC role assignments for the storage account. Specify principal IDs and role definition names."
  type = map(object({
    principal_id         = string
    role_definition_name = string
    principal_type       = optional(string, "User")
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, assignment in var.additional_rbac_assignments :
      contains(["User", "Group", "ServicePrincipal"], assignment.principal_type)
    ])
    error_message = "Principal type must be one of: User, Group, ServicePrincipal."
  }
}

# =============================================================================
# TAGGING AND METADATA VARIABLES
# =============================================================================

variable "tags" {
  description = "A map of tags to assign to all resources. These tags help with resource organization, cost tracking, and governance."
  type        = map(string)
  default = {
    purpose     = "demo"
    environment = "learning"
    recipe      = "basic-file-storage-blob-portal"
    managed_by  = "terraform"
  }

  validation {
    condition = alltrue([
      for key, value in var.tags :
      length(key) <= 512 && length(value) <= 256
    ])
    error_message = "Tag keys must be <= 512 characters and values must be <= 256 characters."
  }
}

variable "resource_prefix" {
  description = "Optional prefix to add to resource names for organization and identification purposes."
  type        = string
  default     = ""

  validation {
    condition     = length(var.resource_prefix) <= 10
    error_message = "Resource prefix must be 10 characters or less."
  }
}

# =============================================================================
# NETWORK SECURITY VARIABLES
# =============================================================================

variable "network_rules" {
  description = "Network access rules for the storage account. Configure IP restrictions and virtual network access."
  type = object({
    default_action = string
    ip_rules       = optional(list(string), [])
    bypass         = optional(list(string), ["AzureServices"])
  })
  default = {
    default_action = "Allow"
    ip_rules       = []
    bypass         = ["AzureServices"]
  }

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "Default action must be either 'Allow' or 'Deny'."
  }

  validation {
    condition = alltrue([
      for rule in var.network_rules.ip_rules :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", rule))
    ])
    error_message = "IP rules must be valid IPv4 addresses or CIDR blocks."
  }
}

# =============================================================================
# OPTIONAL FEATURES VARIABLES
# =============================================================================

variable "enable_versioning" {
  description = "Whether to enable blob versioning for point-in-time recovery and change tracking."
  type        = bool
  default     = false
}

variable "enable_soft_delete" {
  description = "Whether to enable soft delete for blobs and containers to protect against accidental deletion."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs and containers. Only used if soft delete is enabled."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 1 and 365."
  }
}

variable "enable_change_feed" {
  description = "Whether to enable change feed for audit logging and event-driven processing."
  type        = bool
  default     = false
}