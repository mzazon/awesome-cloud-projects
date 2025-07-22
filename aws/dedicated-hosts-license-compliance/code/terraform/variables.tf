# General configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "license-compliance"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# License Manager configuration
variable "windows_license_count" {
  description = "Number of Windows Server socket licenses available"
  type        = number
  default     = 10
  
  validation {
    condition = var.windows_license_count > 0 && var.windows_license_count <= 100
    error_message = "Windows license count must be between 1 and 100."
  }
}

variable "oracle_license_count" {
  description = "Number of Oracle Enterprise Edition core licenses available"
  type        = number
  default     = 16
  
  validation {
    condition = var.oracle_license_count > 0 && var.oracle_license_count <= 200
    error_message = "Oracle license count must be between 1 and 200."
  }
}

# Dedicated Host configuration
variable "dedicated_host_configs" {
  description = "Configuration for dedicated hosts"
  type = map(object({
    instance_family    = string
    availability_zone  = string
    auto_placement     = string
    host_recovery      = string
    license_type       = string
    purpose           = string
  }))
  default = {
    windows_host = {
      instance_family   = "m5"
      availability_zone = "a"
      auto_placement    = "off"
      host_recovery     = "on"
      license_type      = "WindowsServer"
      purpose          = "SQLServer"
    }
    oracle_host = {
      instance_family   = "r5"
      availability_zone = "b"
      auto_placement    = "off"
      host_recovery     = "on"
      license_type      = "Oracle"
      purpose          = "Database"
    }
  }
}

# Instance configuration
variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for instance access"
  type        = string
  default     = ""
}

variable "instance_configs" {
  description = "Configuration for BYOL instances"
  type = map(object({
    instance_type = string
    license_type  = string
    application   = string
  }))
  default = {
    windows_instance = {
      instance_type = "m5.large"
      license_type  = "WindowsServer"
      application   = "SQLServer"
    }
    oracle_instance = {
      instance_type = "r5.xlarge"
      license_type  = "Oracle"
      application   = "Database"
    }
  }
}

# Monitoring and alerting configuration
variable "license_utilization_threshold" {
  description = "License utilization threshold percentage for CloudWatch alarms"
  type        = number
  default     = 80
  
  validation {
    condition = var.license_utilization_threshold >= 50 && var.license_utilization_threshold <= 95
    error_message = "License utilization threshold must be between 50 and 95 percent."
  }
}

variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address or leave empty to skip email notifications."
  }
}

# AWS Config configuration
variable "enable_config" {
  description = "Enable AWS Config for compliance monitoring"
  type        = bool
  default     = true
}

variable "config_delivery_frequency" {
  description = "Frequency for AWS Config snapshot delivery"
  type        = string
  default     = "TwentyFour_Hours"
  
  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Config delivery frequency must be a valid AWS Config frequency."
  }
}

# Systems Manager configuration
variable "enable_ssm_inventory" {
  description = "Enable Systems Manager inventory collection"
  type        = bool
  default     = true
}

variable "ssm_inventory_schedule" {
  description = "Schedule expression for SSM inventory collection"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition = can(regex("^rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)$", var.ssm_inventory_schedule))
    error_message = "SSM inventory schedule must be a valid rate expression (e.g., 'rate(1 day)')."
  }
}

# Cost optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features like automated scheduling"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}