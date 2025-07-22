# Variables for the CodeArtifact artifact management infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project or organization"
  type        = string
  default     = "my-company"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "domain_encryption_key" {
  description = "KMS key ID for CodeArtifact domain encryption. If empty, AWS managed key is used"
  type        = string
  default     = ""
}

variable "npm_store_repository_name" {
  description = "Name of the npm store repository for caching public npm packages"
  type        = string
  default     = "npm-store"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,98}[a-z0-9]$", var.npm_store_repository_name))
    error_message = "Repository name must be 2-100 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "pypi_store_repository_name" {
  description = "Name of the PyPI store repository for caching public Python packages"
  type        = string
  default     = "pypi-store"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,98}[a-z0-9]$", var.pypi_store_repository_name))
    error_message = "Repository name must be 2-100 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "team_repository_name" {
  description = "Name of the team development repository"
  type        = string
  default     = "team-dev"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,98}[a-z0-9]$", var.team_repository_name))
    error_message = "Repository name must be 2-100 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "production_repository_name" {
  description = "Name of the production repository"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,98}[a-z0-9]$", var.production_repository_name))
    error_message = "Repository name must be 2-100 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "enable_npm_external_connection" {
  description = "Enable external connection to public npm registry"
  type        = bool
  default     = true
}

variable "enable_pypi_external_connection" {
  description = "Enable external connection to public PyPI registry"
  type        = bool
  default     = true
}

variable "create_developer_role" {
  description = "Create an IAM role for developers with read/write access to development repositories"
  type        = bool
  default     = true
}

variable "create_production_role" {
  description = "Create an IAM role for production deployments with read-only access to production repository"
  type        = bool
  default     = true
}

variable "developer_role_name" {
  description = "Name of the IAM role for developers"
  type        = string
  default     = "codeartifact-developer-role"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.developer_role_name))
    error_message = "Role name must contain only alphanumeric characters and the following: +=,.@_-"
  }
}

variable "production_role_name" {
  description = "Name of the IAM role for production access"
  type        = string
  default     = "codeartifact-production-role"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.production_role_name))
    error_message = "Role name must contain only alphanumeric characters and the following: +=,.@_-"
  }
}

variable "enable_repository_policy" {
  description = "Enable repository-level permissions policy for the team repository"
  type        = bool
  default     = true
}

variable "allowed_aws_principals" {
  description = "List of AWS principals (ARNs) allowed access to repositories"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.allowed_aws_principals : can(regex("^arn:aws:iam::[0-9]{12}:(root|user|role).*", arn))
    ])
    error_message = "All principals must be valid AWS IAM ARNs."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}