# Environment and naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "budget-alerts"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Budget configuration variables
variable "budget_name" {
  description = "Name of the AWS Budget"
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget amount in USD"
  type        = number
  default     = 100

  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_time_unit" {
  description = "Time unit for the budget (MONTHLY, QUARTERLY, ANNUALLY)"
  type        = string
  default     = "MONTHLY"

  validation {
    condition     = contains(["MONTHLY", "QUARTERLY", "ANNUALLY"], var.budget_time_unit)
    error_message = "Budget time unit must be MONTHLY, QUARTERLY, or ANNUALLY."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for budget notifications"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "notification_thresholds" {
  description = "List of notification thresholds with their configurations"
  type = list(object({
    threshold           = number
    threshold_type      = string
    notification_type   = string
    comparison_operator = string
  }))
  default = [
    {
      threshold           = 80
      threshold_type      = "PERCENTAGE"
      notification_type   = "ACTUAL"
      comparison_operator = "GREATER_THAN"
    },
    {
      threshold           = 90
      threshold_type      = "PERCENTAGE"
      notification_type   = "FORECASTED"
      comparison_operator = "GREATER_THAN"
    },
    {
      threshold           = 100
      threshold_type      = "PERCENTAGE"
      notification_type   = "ACTUAL"
      comparison_operator = "GREATER_THAN"
    }
  ]

  validation {
    condition = alltrue([
      for threshold in var.notification_thresholds :
      threshold.threshold >= 0 && threshold.threshold <= 1000
    ])
    error_message = "All thresholds must be between 0 and 1000."
  }
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Cost type configuration
variable "budget_cost_types" {
  description = "Configuration for budget cost types"
  type = object({
    include_credit            = bool
    include_discount          = bool
    include_other_subscription = bool
    include_recurring         = bool
    include_refund           = bool
    include_subscription     = bool
    include_support          = bool
    include_tax              = bool
    include_upfront          = bool
    use_blended              = bool
    use_amortized            = bool
  })
  default = {
    include_credit            = false
    include_discount          = true
    include_other_subscription = true
    include_recurring         = true
    include_refund           = true
    include_subscription     = true
    include_support          = true
    include_tax              = true
    include_upfront          = true
    use_blended              = false
    use_amortized            = false
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}