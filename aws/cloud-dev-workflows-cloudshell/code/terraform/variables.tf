# AWS region for resource deployment
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z][a-z]-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

# Environment name for resource tagging and naming
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

# Project name for resource naming
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "dev-workflow"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 30
    error_message = "Project name must be between 3 and 30 characters."
  }
}

# CodeCommit repository name
variable "repository_name" {
  description = "Name for the CodeCommit repository"
  type        = string
  default     = ""

  validation {
    condition     = var.repository_name == "" || can(regex("^[a-zA-Z0-9._-]+$", var.repository_name))
    error_message = "Repository name can only contain alphanumeric characters, periods, hyphens, and underscores."
  }
}

# CodeCommit repository description
variable "repository_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "Demo repository for cloud-based development workflow using AWS CloudShell and CodeCommit"

  validation {
    condition     = length(var.repository_description) <= 1000
    error_message = "Repository description must be 1000 characters or less."
  }
}

# IAM user name for CodeCommit access
variable "iam_user_name" {
  description = "Name for the IAM user with CodeCommit access"
  type        = string
  default     = ""

  validation {
    condition     = var.iam_user_name == "" || can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.iam_user_name))
    error_message = "IAM user name can only contain alphanumeric characters and +=,.@_- characters."
  }
}

# Create IAM user for CodeCommit access
variable "create_iam_user" {
  description = "Whether to create an IAM user for CodeCommit access"
  type        = bool
  default     = false
}

# Enable versioning for code artifacts
variable "enable_versioning" {
  description = "Enable versioning for development artifacts"
  type        = bool
  default     = true
}

# Additional tags for resources
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.additional_tags) <= 10
    error_message = "Cannot specify more than 10 additional tags."
  }
}

# CloudShell environment configuration
variable "cloudshell_timeout" {
  description = "CloudShell session timeout in minutes"
  type        = number
  default     = 20

  validation {
    condition     = var.cloudshell_timeout >= 10 && var.cloudshell_timeout <= 120
    error_message = "CloudShell timeout must be between 10 and 120 minutes."
  }
}

# Development team size for capacity planning
variable "team_size" {
  description = "Expected number of developers using this environment"
  type        = number
  default     = 5

  validation {
    condition     = var.team_size >= 1 && var.team_size <= 100
    error_message = "Team size must be between 1 and 100 developers."
  }
}