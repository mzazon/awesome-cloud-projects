# Input variables for budget monitoring infrastructure
# These variables allow customization of the deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "budget_limit_amount" {
  description = "Monthly budget limit amount in USD"
  type        = number
  default     = 100
  
  validation {
    condition = var.budget_limit_amount > 0 && var.budget_limit_amount <= 100000
    error_message = "Budget limit must be between 1 and 100000 USD."
  }
}

variable "notification_email" {
  description = "Email address to receive budget notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "budget_name_prefix" {
  description = "Prefix for budget name (random suffix will be appended)"
  type        = string
  default     = "monthly-cost-budget"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.budget_name_prefix))
    error_message = "Budget name prefix can only contain alphanumeric characters and hyphens."
  }
}

variable "sns_topic_name_prefix" {
  description = "Prefix for SNS topic name (random suffix will be appended)"
  type        = string
  default     = "budget-alerts"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.sns_topic_name_prefix))
    error_message = "SNS topic name prefix can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "actual_threshold_80" {
  description = "Threshold percentage for actual spending alert (80%)"
  type        = number
  default     = 80
  
  validation {
    condition = var.actual_threshold_80 > 0 && var.actual_threshold_80 <= 100
    error_message = "Threshold must be between 1 and 100."
  }
}

variable "actual_threshold_100" {
  description = "Threshold percentage for actual spending alert (100%)"
  type        = number
  default     = 100
  
  validation {
    condition = var.actual_threshold_100 > 0 && var.actual_threshold_100 <= 200
    error_message = "Threshold must be between 1 and 200."
  }
}

variable "forecast_threshold_80" {
  description = "Threshold percentage for forecasted spending alert (80%)"
  type        = number
  default     = 80
  
  validation {
    condition = var.forecast_threshold_80 > 0 && var.forecast_threshold_80 <= 100
    error_message = "Forecast threshold must be between 1 and 100."
  }
}

variable "include_credits" {
  description = "Whether to include credits in cost calculation"
  type        = bool
  default     = true
}

variable "include_discounts" {
  description = "Whether to include discounts in cost calculation"
  type        = bool
  default     = true
}

variable "include_support_costs" {
  description = "Whether to include support costs in budget calculation"
  type        = bool
  default     = true
}

variable "include_taxes" {
  description = "Whether to include taxes in budget calculation"
  type        = bool
  default     = true
}

variable "budget_time_unit" {
  description = "Time unit for budget period"
  type        = string
  default     = "MONTHLY"
  
  validation {
    condition = contains(["DAILY", "MONTHLY", "QUARTERLY", "ANNUALLY"], var.budget_time_unit)
    error_message = "Budget time unit must be one of: DAILY, MONTHLY, QUARTERLY, ANNUALLY."
  }
}