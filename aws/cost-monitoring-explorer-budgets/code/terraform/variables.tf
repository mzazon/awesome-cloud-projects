# AWS region where resources will be created
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Environment tag for resource identification
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# Email address for budget notifications
variable "notification_email" {
  description = "Email address to receive budget alert notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must provide a valid email address for notifications."
  }
}

# Monthly budget limit in USD
variable "budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 100.00
  
  validation {
    condition = var.budget_limit > 0 && var.budget_limit <= 10000
    error_message = "Budget limit must be between $1 and $10,000."
  }
}

# Budget name prefix (random suffix will be added)
variable "budget_name_prefix" {
  description = "Prefix for the budget name (random suffix will be added for uniqueness)"
  type        = string
  default     = "monthly-cost-budget"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.budget_name_prefix))
    error_message = "Budget name prefix can only contain alphanumeric characters and hyphens."
  }
}

# SNS topic name prefix (random suffix will be added)
variable "sns_topic_prefix" {
  description = "Prefix for the SNS topic name (random suffix will be added for uniqueness)"
  type        = string
  default     = "budget-alerts"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.sns_topic_prefix))
    error_message = "SNS topic prefix can only contain alphanumeric characters, hyphens, and underscores."
  }
}

# Budget alert thresholds for actual spending
variable "actual_alert_thresholds" {
  description = "List of percentage thresholds for actual spending alerts"
  type        = list(number)
  default     = [50, 75, 90]
  
  validation {
    condition = alltrue([
      for threshold in var.actual_alert_thresholds : 
      threshold > 0 && threshold <= 100
    ])
    error_message = "All alert thresholds must be between 1 and 100 percent."
  }
}

# Budget alert threshold for forecasted spending
variable "forecasted_alert_threshold" {
  description = "Percentage threshold for forecasted spending alert"
  type        = number
  default     = 100
  
  validation {
    condition = var.forecasted_alert_threshold > 0 && var.forecasted_alert_threshold <= 200
    error_message = "Forecasted alert threshold must be between 1 and 200 percent."
  }
}

# Include tax in budget calculations
variable "include_tax" {
  description = "Whether to include tax in budget cost calculations"
  type        = bool
  default     = true
}

# Include subscription costs in budget calculations
variable "include_subscription" {
  description = "Whether to include subscription costs in budget calculations"
  type        = bool
  default     = true
}

# Include support charges in budget calculations
variable "include_support" {
  description = "Whether to include support charges in budget calculations"
  type        = bool
  default     = true
}

# Include upfront costs in budget calculations
variable "include_upfront" {
  description = "Whether to include upfront costs in budget calculations"
  type        = bool
  default     = true
}

# Include recurring costs in budget calculations
variable "include_recurring" {
  description = "Whether to include recurring costs in budget calculations"
  type        = bool
  default     = true
}

# Additional tags to apply to all resources
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)  
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags :
      can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", key)) &&
      can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", value))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}