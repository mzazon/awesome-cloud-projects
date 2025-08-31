# Input Variables for Infrastructure Monitoring Quick Setup
# This file defines all configurable parameters for the monitoring infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
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

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "infrastructure-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 1 and 100."
  }
}

variable "disk_alarm_threshold" {
  description = "Disk usage threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.disk_alarm_threshold > 0 && var.disk_alarm_threshold <= 100
    error_message = "Disk alarm threshold must be between 1 and 100."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be one of the valid CloudWatch log retention periods."
  }
}

variable "application_log_retention_days" {
  description = "Number of days to retain application CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.application_log_retention_days)
    error_message = "Application log retention must be one of the valid CloudWatch log retention periods."
  }
}

variable "metrics_collection_interval" {
  description = "CloudWatch Agent metrics collection interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.metrics_collection_interval >= 60 && var.metrics_collection_interval <= 3600
    error_message = "Metrics collection interval must be between 60 and 3600 seconds."
  }
}

variable "patch_scan_schedule" {
  description = "Schedule expression for patch scanning (rate or cron format)"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.patch_scan_schedule))
    error_message = "Schedule must be in AWS schedule expression format (rate() or cron())."
  }
}

variable "inventory_collection_schedule" {
  description = "Schedule expression for inventory collection (rate or cron format)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.inventory_collection_schedule))
    error_message = "Schedule must be in AWS schedule expression format (rate() or cron())."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for CloudWatch Agent"
  type        = bool
  default     = true
}

variable "enable_compliance_monitoring" {
  description = "Enable Systems Manager compliance monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "target_tag_key" {
  description = "EC2 tag key for targeting instances in SSM associations"
  type        = string
  default     = "Environment"
}

variable "target_tag_values" {
  description = "List of EC2 tag values for targeting instances in SSM associations"
  type        = list(string)
  default     = ["*"]
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  type        = string
  default     = "CWAgent"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9._/-]*$", var.cloudwatch_namespace))
    error_message = "CloudWatch namespace must start with a letter and contain only letters, numbers, periods, hyphens, underscores, and forward slashes."
  }
}