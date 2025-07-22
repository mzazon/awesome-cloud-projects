# Common variables
variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "development"
  
  validation {
    condition     = can(regex("^(development|staging|production)$", var.environment))
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "manufacturing-plant"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must only contain alphanumeric characters and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# IoT SiteWise specific variables
variable "asset_model_name" {
  description = "Name for the IoT SiteWise asset model"
  type        = string
  default     = "ProductionLineEquipment"
}

variable "asset_model_description" {
  description = "Description for the IoT SiteWise asset model"
  type        = string
  default     = "Model for production line machinery"
}

variable "asset_name" {
  description = "Name for the IoT SiteWise asset instance"
  type        = string
  default     = "ProductionLine-A-Pump-001"
}

variable "gateway_name" {
  description = "Name for the IoT SiteWise gateway"
  type        = string
  default     = "manufacturing-gateway"
}

# Timestream specific variables
variable "timestream_database_name" {
  description = "Name for the Timestream database"
  type        = string
  default     = "industrial-data"
}

variable "timestream_table_name" {
  description = "Name for the Timestream table"
  type        = string
  default     = "equipment-metrics"
}

variable "timestream_memory_retention_hours" {
  description = "Memory store retention period in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.timestream_memory_retention_hours >= 1 && var.timestream_memory_retention_hours <= 8766
    error_message = "Memory retention hours must be between 1 and 8766."
  }
}

variable "timestream_magnetic_retention_days" {
  description = "Magnetic store retention period in days"
  type        = number
  default     = 365
  
  validation {
    condition     = var.timestream_magnetic_retention_days >= 1 && var.timestream_magnetic_retention_days <= 73000
    error_message = "Magnetic retention days must be between 1 and 73000."
  }
}

# CloudWatch specific variables
variable "temperature_alarm_threshold" {
  description = "Temperature threshold for CloudWatch alarm"
  type        = number
  default     = 80.0
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarm"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
}

# SNS Topic variables
variable "create_sns_topic" {
  description = "Whether to create SNS topic for alerts"
  type        = bool
  default     = true
}

variable "sns_topic_name" {
  description = "Name for the SNS topic for equipment alerts"
  type        = string
  default     = "equipment-alerts"
}

variable "email_notification_endpoint" {
  description = "Email address for equipment alert notifications"
  type        = string
  default     = ""
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}