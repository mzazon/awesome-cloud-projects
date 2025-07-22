# General Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create for the migration resources"
  type        = string
  default     = "rg-migration-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.resource_group_name))
    error_message = "Resource group name must be valid Azure resource group name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "migration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Storage Configuration Variables
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either Hot or Cool."
  }
}

variable "target_container_name" {
  description = "Name of the target container for migrated data"
  type        = string
  default     = "migrated-data"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.target_container_name))
    error_message = "Container name must be lowercase, start and end with alphanumeric characters, and contain only alphanumeric characters and hyphens."
  }
}

# AWS Source Configuration Variables
variable "aws_s3_bucket_name" {
  description = "Name of the source AWS S3 bucket"
  type        = string
  default     = "your-source-s3-bucket"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.aws_s3_bucket_name))
    error_message = "S3 bucket name must be valid AWS S3 bucket name."
  }
}

variable "aws_account_id" {
  description = "AWS account ID for the source S3 bucket"
  type        = string
  default     = "123456789012"
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS account ID must be a 12-digit number."
  }
}

variable "aws_region" {
  description = "AWS region where the source S3 bucket is located"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "ca-central-1", "eu-central-1", "eu-west-1", "eu-west-2",
      "eu-west-3", "eu-north-1", "ap-southeast-1", "ap-southeast-2",
      "ap-northeast-1", "ap-northeast-2", "ap-south-1", "sa-east-1"
    ], var.aws_region)
    error_message = "AWS region must be a valid AWS region."
  }
}

# Monitoring Configuration Variables
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "metric_alert_evaluation_frequency" {
  description = "How often the metric alert rule runs (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.metric_alert_evaluation_frequency)
    error_message = "Evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "metric_alert_window_size" {
  description = "The period of time that is used to monitor alert activity (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT1D"], var.metric_alert_window_size)
    error_message = "Window size must be one of: PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, PT1D."
  }
}

# Notification Configuration Variables
variable "notification_email" {
  description = "Email address for migration notifications"
  type        = string
  default     = "admin@yourcompany.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "enable_teams_notifications" {
  description = "Enable Microsoft Teams notifications"
  type        = bool
  default     = false
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# Storage Mover Configuration Variables
variable "storage_mover_description" {
  description = "Description for the Storage Mover resource"
  type        = string
  default     = "Multi-cloud migration from AWS S3 to Azure Blob Storage"
}

variable "migration_project_name" {
  description = "Name for the migration project"
  type        = string
  default     = "s3-to-blob-migration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.migration_project_name))
    error_message = "Migration project name must contain only alphanumeric characters and hyphens."
  }
}

variable "migration_copy_mode" {
  description = "Copy mode for the migration job"
  type        = string
  default     = "Mirror"
  
  validation {
    condition     = contains(["Mirror", "Additive"], var.migration_copy_mode)
    error_message = "Copy mode must be either Mirror or Additive."
  }
}

# Logic App Configuration Variables
variable "enable_logic_app" {
  description = "Enable Logic App for migration automation"
  type        = bool
  default     = true
}

variable "logic_app_trigger_type" {
  description = "Trigger type for the Logic App"
  type        = string
  default     = "Manual"
  
  validation {
    condition     = contains(["Manual", "Recurrence", "HTTP"], var.logic_app_trigger_type)
    error_message = "Logic App trigger type must be one of: Manual, Recurrence, HTTP."
  }
}

# Tagging Variables
variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}