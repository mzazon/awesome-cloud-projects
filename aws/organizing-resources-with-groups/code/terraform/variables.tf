# Core configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and grouping"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "application" {
  description = "Application name for resource tagging and grouping"
  type        = string
  default     = "web-app"
  
  validation {
    condition     = length(var.application) > 0 && length(var.application) <= 50
    error_message = "Application name must be between 1 and 50 characters."
  }
}

variable "deployed_by" {
  description = "Name or identifier of who deployed this infrastructure"
  type        = string
  default     = "terraform"
  
  validation {
    condition     = length(var.deployed_by) > 0
    error_message = "Deployed by field cannot be empty."
  }
}

# Resource naming configuration
variable "resource_name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "rg-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_name_prefix))
    error_message = "Resource name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# CloudWatch Configuration
variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alarm_threshold >= 50 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 50 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to threshold"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Evaluation periods must be between 1 and 10."
  }
}

# Budget Configuration
variable "monthly_budget_limit" {
  description = "Monthly budget limit for resource group cost tracking (USD)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Budget limit must be greater than 0."
  }
}

variable "budget_threshold_percentage" {
  description = "Budget threshold percentage for notifications"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_threshold_percentage >= 50 && var.budget_threshold_percentage <= 100
    error_message = "Budget threshold must be between 50 and 100."
  }
}

# Systems Manager Configuration
variable "enable_automation_documents" {
  description = "Enable Systems Manager automation documents"
  type        = bool
  default     = true
}

variable "enable_eventbridge_tagging_rules" {
  description = "Enable EventBridge rules for automated resource tagging"
  type        = bool
  default     = true
}

# Cost Management Configuration
variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection for the resource group"
  type        = bool
  default     = true
}

# Resource Group Configuration
variable "additional_resource_types" {
  description = "Additional AWS resource types to include in the resource group filter"
  type        = list(string)
  default     = ["AWS::AllSupported"]
  
  validation {
    condition     = length(var.additional_resource_types) > 0
    error_message = "At least one resource type must be specified."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9+\\-=._:/@ ]+$", k))
    ])
    error_message = "Tag keys must contain only valid characters."
  }
}

# CloudWatch Dashboard Configuration
variable "dashboard_period" {
  description = "Period for CloudWatch dashboard metrics (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 3600, 21600, 86400], var.dashboard_period)
    error_message = "Dashboard period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

# EventBridge Configuration
variable "eventbridge_monitored_services" {
  description = "AWS services to monitor for automatic resource tagging"
  type        = list(string)
  default     = ["ec2.amazonaws.com", "s3.amazonaws.com", "rds.amazonaws.com"]
  
  validation {
    condition = alltrue([
      for service in var.eventbridge_monitored_services : can(regex("^[a-z0-9-]+\\.amazonaws\\.com$", service))
    ])
    error_message = "Each service must be in the format 'service.amazonaws.com'."
  }
}