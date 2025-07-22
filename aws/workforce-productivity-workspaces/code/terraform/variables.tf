# =============================================================================
# Variables for AWS WorkSpaces Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "workforce-productivity"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_1_cidr" {
  description = "CIDR block for the first private subnet"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_1_cidr, 0))
    error_message = "Private subnet 1 CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for the second private subnet"
  type        = string
  default     = "10.0.3.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_2_cidr, 0))
    error_message = "Private subnet 2 CIDR must be a valid IPv4 CIDR block."
  }
}

# -----------------------------------------------------------------------------
# Directory Service Configuration
# -----------------------------------------------------------------------------

variable "directory_name" {
  description = "Name for the Simple AD directory"
  type        = string
  default     = "workspaces.local"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.directory_name))
    error_message = "Directory name must contain only alphanumeric characters, dots, and hyphens."
  }
}

variable "directory_password" {
  description = "Password for the Simple AD directory administrator"
  type        = string
  sensitive   = true

  validation {
    condition = length(var.directory_password) >= 8 && length(var.directory_password) <= 64 && can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)", var.directory_password))
    error_message = "Directory password must be 8-64 characters long and contain at least one lowercase letter, one uppercase letter, and one number."
  }
}

variable "directory_size" {
  description = "Size of the Simple AD directory"
  type        = string
  default     = "Small"

  validation {
    condition     = contains(["Small", "Large"], var.directory_size)
    error_message = "Directory size must be either 'Small' or 'Large'."
  }
}

# -----------------------------------------------------------------------------
# WorkSpaces Configuration
# -----------------------------------------------------------------------------

variable "workspace_bundle_id" {
  description = "Bundle ID for WorkSpaces. Leave empty to use default Standard Windows bundle"
  type        = string
  default     = ""
}

variable "workspace_compute_type" {
  description = "Compute type for WorkSpaces"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "VALUE", "STANDARD", "PERFORMANCE", "POWER", "GRAPHICS", 
      "POWERPRO", "GRAPHICSPRO", "GRAPHICS_G4DN", "GRAPHICSPRO_G4DN"
    ], var.workspace_compute_type)
    error_message = "Workspace compute type must be a valid WorkSpaces compute type."
  }
}

variable "workspace_running_mode" {
  description = "Running mode for WorkSpaces (ALWAYS_ON or AUTO_STOP)"
  type        = string
  default     = "AUTO_STOP"

  validation {
    condition     = contains(["ALWAYS_ON", "AUTO_STOP"], var.workspace_running_mode)
    error_message = "Workspace running mode must be either 'ALWAYS_ON' or 'AUTO_STOP'."
  }
}

variable "workspace_auto_stop_timeout" {
  description = "Auto-stop timeout in minutes for WorkSpaces (only applicable when running_mode is AUTO_STOP)"
  type        = number
  default     = 60

  validation {
    condition     = var.workspace_auto_stop_timeout >= 60 && var.workspace_auto_stop_timeout <= 36000
    error_message = "Auto-stop timeout must be between 60 and 36000 minutes."
  }
}

variable "workspace_user_volume_size" {
  description = "Size of the user volume in GiB"
  type        = number
  default     = 50

  validation {
    condition     = var.workspace_user_volume_size >= 10 && var.workspace_user_volume_size <= 2000
    error_message = "User volume size must be between 10 and 2000 GiB."
  }
}

variable "workspace_root_volume_size" {
  description = "Size of the root volume in GiB"
  type        = number
  default     = 80

  validation {
    condition     = var.workspace_root_volume_size >= 80 && var.workspace_root_volume_size <= 2000
    error_message = "Root volume size must be between 80 and 2000 GiB."
  }
}

variable "workspace_encryption_key_id" {
  description = "KMS key ID for WorkSpace volume encryption. Leave empty to use AWS managed key"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Sample WorkSpace Configuration
# -----------------------------------------------------------------------------

variable "create_sample_workspace" {
  description = "Whether to create a sample WorkSpace for testing"
  type        = bool
  default     = false
}

variable "sample_workspace_username" {
  description = "Username for the sample WorkSpace"
  type        = string
  default     = "testuser"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.sample_workspace_username))
    error_message = "Username must contain only alphanumeric characters, dots, underscores, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# WorkSpaces Access and Security Configuration
# -----------------------------------------------------------------------------

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access WorkSpaces"
  type = list(object({
    cidr        = string
    description = string
  }))
  default = [
    {
      cidr        = "0.0.0.0/0"
      description = "Allow all IPs (not recommended for production)"
    }
  ]

  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges : can(cidrhost(ip_range.cidr, 0))
    ])
    error_message = "All IP ranges must be valid IPv4 CIDR blocks."
  }
}

variable "self_service_permissions" {
  description = "Self-service permissions for WorkSpaces users"
  type = object({
    change_compute_type  = string
    increase_volume_size = string
    rebuild_workspace    = string
    restart_workspace    = string
    switch_running_mode  = string
  })
  default = {
    change_compute_type  = "ENABLED"
    increase_volume_size = "ENABLED"
    rebuild_workspace    = "ENABLED"
    restart_workspace    = "ENABLED"
    switch_running_mode  = "ENABLED"
  }

  validation {
    condition = alltrue([
      contains(["ENABLED", "DISABLED"], var.self_service_permissions.change_compute_type),
      contains(["ENABLED", "DISABLED"], var.self_service_permissions.increase_volume_size),
      contains(["ENABLED", "DISABLED"], var.self_service_permissions.rebuild_workspace),
      contains(["ENABLED", "DISABLED"], var.self_service_permissions.restart_workspace),
      contains(["ENABLED", "DISABLED"], var.self_service_permissions.switch_running_mode)
    ])
    error_message = "All self-service permissions must be either 'ENABLED' or 'DISABLED'."
  }
}

variable "workspace_access_properties" {
  description = "Device access properties for WorkSpaces"
  type = object({
    device_type_android    = string
    device_type_chromeos   = string
    device_type_ios        = string
    device_type_linux      = string
    device_type_osx        = string
    device_type_web        = string
    device_type_windows    = string
    device_type_zeroclient = string
  })
  default = {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "DENY"
    device_type_osx        = "ALLOW"
    device_type_web        = "DENY"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "DENY"
  }

  validation {
    condition = alltrue([
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_android),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_chromeos),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_ios),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_linux),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_osx),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_web),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_windows),
      contains(["ALLOW", "DENY"], var.workspace_access_properties.device_type_zeroclient)
    ])
    error_message = "All device access properties must be either 'ALLOW' or 'DENY'."
  }
}

variable "workspace_creation_properties" {
  description = "Properties for WorkSpace creation"
  type = object({
    default_ou                          = string
    enable_internet_access              = bool
    enable_maintenance_mode             = bool
    user_enabled_as_local_administrator = bool
  })
  default = {
    default_ou                          = ""
    enable_internet_access              = true
    enable_maintenance_mode             = true
    user_enabled_as_local_administrator = false
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Monitoring Configuration
# -----------------------------------------------------------------------------

variable "enable_cloudwatch_alarms" {
  description = "Whether to enable CloudWatch alarms for WorkSpaces monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "cloudwatch_alarm_actions" {
  description = "List of ARNs to notify when CloudWatch alarms are triggered"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.cloudwatch_alarm_actions : can(regex("^arn:aws:", arn))
    ])
    error_message = "All alarm action ARNs must be valid AWS ARNs."
  }
}

variable "notification_email" {
  description = "Email address for SNS notifications (only used if no cloudwatch_alarm_actions provided)"
  type        = string
  default     = ""

  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}