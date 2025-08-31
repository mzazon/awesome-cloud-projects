# ===============================================
# Variables for Simple Configuration Management
# with Parameter Store and CloudShell
# ===============================================

# ===============================================
# Application Configuration Variables
# ===============================================

variable "application_name" {
  description = "Name of the application for parameter organization"
  type        = string
  default     = "myapp"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.application_name))
    error_message = "Application name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "dev",
      "staging", "stage", 
      "production", "prod",
      "testing", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, dev, staging, stage, production, prod, testing, test."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ===============================================
# Parameter Store Configuration Variables
# ===============================================

# Standard String Parameters
variable "database_url" {
  description = "Database connection URL for the application"
  type        = string
  default     = "postgresql://db.example.com:5432/myapp"
  sensitive   = false
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://", var.database_url))
    error_message = "Database URL must be a valid URL format."
  }
}

variable "application_port" {
  description = "Port number for the application to listen on"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.application_port > 0 && var.application_port <= 65535
    error_message = "Application port must be between 1 and 65535."
  }
}

variable "debug_mode" {
  description = "Enable debug mode for the application"
  type        = bool
  default     = true
}

# Secure String Parameters
variable "third_party_api_key" {
  description = "Third-party API key for external service integration"
  type        = string
  default     = "api-key-12345-secret-value"
  sensitive   = true
  
  validation {
    condition     = length(var.third_party_api_key) >= 8
    error_message = "API key must be at least 8 characters long."
  }
}

variable "database_password" {
  description = "Database password for application connection"
  type        = string
  default     = "super-secure-password-123"
  sensitive   = true
  
  validation {
    condition     = length(var.database_password) >= 12
    error_message = "Database password must be at least 12 characters long."
  }
}

variable "jwt_secret_key" {
  description = "JWT secret key for token signing and validation"
  type        = string
  default     = "jwt-super-secret-key-for-token-signing-2024"
  sensitive   = true
  
  validation {
    condition     = length(var.jwt_secret_key) >= 32
    error_message = "JWT secret key must be at least 32 characters long for security."
  }
}

# StringList Parameters
variable "allowed_origins" {
  description = "List of allowed CORS origins for the API"
  type        = list(string)
  default = [
    "https://app.example.com",
    "https://admin.example.com", 
    "https://mobile.example.com"
  ]
  
  validation {
    condition = alltrue([
      for origin in var.allowed_origins : can(regex("^https?://", origin))
    ])
    error_message = "All allowed origins must be valid HTTP or HTTPS URLs."
  }
}

variable "deployment_regions" {
  description = "List of AWS regions where the application can be deployed"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
  
  validation {
    condition = alltrue([
      for region in var.deployment_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))
    ])
    error_message = "All deployment regions must be valid AWS region names (e.g., us-east-1)."
  }
}

variable "enabled_features" {
  description = "List of enabled feature flags for the application"
  type        = list(string)
  default = [
    "user-analytics",
    "advanced-logging",
    "performance-monitoring",
    "beta-ui"
  ]
  
  validation {
    condition = alltrue([
      for feature in var.enabled_features : can(regex("^[a-z][a-z0-9-]*$", feature))
    ])
    error_message = "Feature flags must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# ===============================================
# KMS Configuration Variables
# ===============================================

variable "create_kms_key" {
  description = "Whether to create a custom KMS key for parameter encryption"
  type        = bool
  default     = true
}

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting the KMS key (7-30 days)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# ===============================================
# IAM Configuration Variables
# ===============================================

variable "create_cloudshell_role" {
  description = "Whether to create an IAM role for CloudShell Parameter Store access"
  type        = bool
  default     = false
}

# ===============================================
# Advanced Configuration Variables
# ===============================================

variable "parameter_tier" {
  description = "Parameter tier for all created parameters (Standard or Advanced)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Advanced"], var.parameter_tier)
    error_message = "Parameter tier must be either 'Standard' or 'Advanced'."
  }
}

variable "enable_parameter_policies" {
  description = "Whether to enable parameter policies for advanced parameters"
  type        = bool
  default     = false
}

variable "parameter_data_type" {
  description = "Data type for parameters (text or aws:ec2:image)"
  type        = string
  default     = "text"
  
  validation {
    condition     = contains(["text", "aws:ec2:image"], var.parameter_data_type)
    error_message = "Parameter data type must be either 'text' or 'aws:ec2:image'."
  }
}

# ===============================================
# Organizational Variables  
# ===============================================

variable "cost_center" {
  description = "Cost center for resource allocation and billing"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Project identifier for resource organization"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = ""
}

variable "contact_email" {
  description = "Contact email for the resource owner"
  type        = string
  default     = ""
  
  validation {
    condition = var.contact_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.contact_email))
    error_message = "Contact email must be a valid email address or empty string."
  }
}

# ===============================================
# Feature Toggle Variables
# ===============================================

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring for Parameter Store parameters"
  type        = bool
  default     = false
}

variable "enable_backup" {
  description = "Enable automated backup of parameter configurations"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable parameter versioning and history tracking"
  type        = bool
  default     = true
}