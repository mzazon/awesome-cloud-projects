# AWS Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID (automatically retrieved if not provided)"
  type        = string
  default     = ""
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "iot-fleet"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# IoT Fleet Configuration
variable "device_count" {
  description = "Number of IoT devices to register in the fleet"
  type        = number
  default     = 3
  
  validation {
    condition     = var.device_count >= 1 && var.device_count <= 100
    error_message = "Device count must be between 1 and 100."
  }
}

variable "thing_group_name" {
  description = "Name for the IoT Thing Group (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "iot_policy_name" {
  description = "Name for the IoT Policy (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

# Firmware Configuration
variable "firmware_version" {
  description = "Version of the firmware to deploy"
  type        = string
  default     = "v2.1.0"
  
  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.firmware_version))
    error_message = "Firmware version must follow semantic versioning format (e.g., v2.1.0)."
  }
}

variable "firmware_content" {
  description = "Content of the firmware file (for demo purposes)"
  type        = string
  default     = "Firmware update package v2.1.0 - Demo content"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket storing firmware files (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "s3_bucket_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

# Job Configuration
variable "job_rollout_max_per_minute" {
  description = "Maximum number of devices to update per minute"
  type        = number
  default     = 10
  
  validation {
    condition     = var.job_rollout_max_per_minute >= 1 && var.job_rollout_max_per_minute <= 100
    error_message = "Job rollout max per minute must be between 1 and 100."
  }
}

variable "job_abort_threshold_percentage" {
  description = "Percentage of failed jobs that triggers job abortion"
  type        = number
  default     = 25
  
  validation {
    condition     = var.job_abort_threshold_percentage >= 1 && var.job_abort_threshold_percentage <= 100
    error_message = "Job abort threshold percentage must be between 1 and 100."
  }
}

variable "job_timeout_minutes" {
  description = "Timeout for job execution in minutes"
  type        = number
  default     = 60
  
  validation {
    condition     = var.job_timeout_minutes >= 5 && var.job_timeout_minutes <= 1440
    error_message = "Job timeout must be between 5 and 1440 minutes."
  }
}

# Device Attributes
variable "device_type" {
  description = "Type of IoT devices in the fleet"
  type        = string
  default     = "sensor"
}

variable "device_location_prefix" {
  description = "Prefix for device location attribute"
  type        = string
  default     = "factory-floor"
}

variable "initial_firmware_version" {
  description = "Initial firmware version for newly registered devices"
  type        = string
  default     = "v2.0.0"
}

# CloudWatch Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for IoT operations"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Security Configuration
variable "enable_certificate_auto_registration" {
  description = "Enable automatic certificate registration for devices"
  type        = bool
  default     = false
}

variable "certificate_ca_certificate_pem" {
  description = "CA certificate PEM for device certificate validation (required if auto-registration enabled)"
  type        = string
  default     = ""
  sensitive   = true
}

# Tagging Configuration
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "IoT Fleet Management"
    ManagedBy   = "Terraform"
    Environment = "development"
    Recipe      = "iot-fleet-management-ota-updates"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}