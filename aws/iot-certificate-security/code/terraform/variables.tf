# Variables for IoT Security implementation
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "iot-security-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "thing_type_name" {
  description = "Name for the IoT Thing Type"
  type        = string
  default     = "IndustrialSensor"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9:_-]+$", var.thing_type_name))
    error_message = "Thing type name must contain only alphanumeric characters, colons, underscores, and hyphens."
  }
}

variable "device_prefix" {
  description = "Prefix for IoT device names"
  type        = string
  default     = "sensor"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.device_prefix))
    error_message = "Device prefix must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "number_of_devices" {
  description = "Number of IoT devices to create"
  type        = number
  default     = 3
  
  validation {
    condition     = var.number_of_devices > 0 && var.number_of_devices <= 100
    error_message = "Number of devices must be between 1 and 100."
  }
}

variable "factory_locations" {
  description = "List of factory locations for device attributes"
  type        = list(string)
  default     = ["factory-001", "factory-002", "factory-003"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_device_defender" {
  description = "Enable AWS IoT Device Defender security monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alerting"
  type        = bool
  default     = true
}

variable "certificate_expiry_threshold_days" {
  description = "Number of days before certificate expiry to trigger alerts"
  type        = number
  default     = 30
  
  validation {
    condition     = var.certificate_expiry_threshold_days > 0 && var.certificate_expiry_threshold_days <= 365
    error_message = "Certificate expiry threshold must be between 1 and 365 days."
  }
}

variable "max_connections_threshold" {
  description = "Maximum number of concurrent connections per device before triggering alert"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_connections_threshold > 0
    error_message = "Max connections threshold must be greater than 0."
  }
}

variable "authorization_failures_threshold" {
  description = "Number of authorization failures before triggering alert"
  type        = number
  default     = 5
  
  validation {
    condition     = var.authorization_failures_threshold > 0
    error_message = "Authorization failures threshold must be greater than 0."
  }
}

variable "message_size_threshold_bytes" {
  description = "Maximum message size in bytes before triggering alert"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.message_size_threshold_bytes > 0
    error_message = "Message size threshold must be greater than 0."
  }
}

variable "enable_time_based_access" {
  description = "Enable time-based access policies (business hours only)"
  type        = bool
  default     = false
}

variable "business_hours_start" {
  description = "Business hours start time (UTC, 24-hour format)"
  type        = string
  default     = "08:00:00Z"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$", var.business_hours_start))
    error_message = "Business hours start must be in format HH:MM:SSZ (UTC)."
  }
}

variable "business_hours_end" {
  description = "Business hours end time (UTC, 24-hour format)"
  type        = string
  default     = "18:00:00Z"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$", var.business_hours_end))
    error_message = "Business hours end must be in format HH:MM:SSZ (UTC)."
  }
}

variable "enable_location_based_access" {
  description = "Enable location-based access policies"
  type        = bool
  default     = true
}

variable "enable_automated_compliance" {
  description = "Enable automated compliance monitoring with AWS Config"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for security alert notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}