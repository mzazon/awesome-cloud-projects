# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "devenv-automation"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 3-30 characters long."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# WorkSpaces configuration
variable "directory_id" {
  description = "Active Directory ID for WorkSpaces integration"
  type        = string
  validation {
    condition = can(regex("^d-[0-9a-f]{10}$", var.directory_id))
    error_message = "Directory ID must be in the format 'd-xxxxxxxxxx' where x is a hexadecimal character."
  }
}

variable "workspaces_bundle_id" {
  description = "Bundle ID for WorkSpaces (Standard, Performance, Power, PowerPro, Graphics, GraphicsPro)"
  type        = string
  default     = "wsb-b0s22j3d7"  # Standard bundle with Windows 10
  validation {
    condition = can(regex("^wsb-[0-9a-z]{8,}$", var.workspaces_bundle_id))
    error_message = "Bundle ID must be in the format 'wsb-xxxxxxxx' where x is alphanumeric."
  }
}

variable "target_users" {
  description = "List of Active Directory users who should have WorkSpaces"
  type        = list(string)
  default     = ["developer1", "developer2", "developer3"]
  validation {
    condition = length(var.target_users) > 0 && length(var.target_users) <= 25
    error_message = "Target users list must contain 1-25 users."
  }
}

variable "workspaces_running_mode" {
  description = "Running mode for WorkSpaces (ALWAYS_ON or AUTO_STOP)"
  type        = string
  default     = "AUTO_STOP"
  validation {
    condition = contains(["ALWAYS_ON", "AUTO_STOP"], var.workspaces_running_mode)
    error_message = "Running mode must be either 'ALWAYS_ON' or 'AUTO_STOP'."
  }
}

variable "auto_stop_timeout_minutes" {
  description = "Auto-stop timeout in minutes (only applies to AUTO_STOP mode)"
  type        = number
  default     = 60
  validation {
    condition = var.auto_stop_timeout_minutes >= 60 && var.auto_stop_timeout_minutes <= 120
    error_message = "Auto-stop timeout must be between 60 and 120 minutes."
  }
}

# Active Directory credentials
variable "ad_service_username" {
  description = "Active Directory service account username for WorkSpaces automation"
  type        = string
  default     = "workspaces-service"
  sensitive   = true
}

variable "ad_service_password" {
  description = "Active Directory service account password for WorkSpaces automation"
  type        = string
  sensitive   = true
  validation {
    condition = length(var.ad_service_password) >= 8
    error_message = "AD service password must be at least 8 characters long."
  }
}

# Development tools configuration
variable "development_tools" {
  description = "Comma-separated list of development tools to install"
  type        = string
  default     = "git,vscode,nodejs,python,docker"
}

variable "team_configuration" {
  description = "Team-specific configuration settings"
  type        = string
  default     = "standard"
  validation {
    condition = contains(["standard", "frontend", "backend", "fullstack", "devops", "datascience"], var.team_configuration)
    error_message = "Team configuration must be one of: standard, frontend, backend, fullstack, devops, datascience."
  }
}

# Lambda function configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

# EventBridge scheduling
variable "automation_schedule" {
  description = "EventBridge schedule expression for automation (e.g., 'rate(24 hours)' or 'cron(0 9 * * ? *)')"
  type        = string
  default     = "rate(24 hours)"
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.automation_schedule))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

variable "enable_automation_schedule" {
  description = "Whether to enable the EventBridge automation schedule"
  type        = bool
  default     = true
}

# Security and encryption
variable "enable_user_volume_encryption" {
  description = "Enable encryption for user volumes in WorkSpaces"
  type        = bool
  default     = true
}

variable "enable_root_volume_encryption" {
  description = "Enable encryption for root volumes in WorkSpaces"
  type        = bool
  default     = true
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}