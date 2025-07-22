# Input variables for the cost allocation and chargeback system

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cost-allocation"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "notification_email" {
  description = "Email address for cost allocation notifications"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.notification_email)) || var.notification_email == ""
    error_message = "Must be a valid email address or empty string."
  }
}

variable "cost_allocation_tags" {
  description = "List of cost allocation tags to activate"
  type        = list(string)
  default     = ["Department", "Project", "Team", "Environment"]
}

variable "department_budgets" {
  description = "Department budget configurations"
  type = map(object({
    amount              = number
    threshold_percent   = number
    department_values   = list(string)
  }))
  default = {
    engineering = {
      amount            = 1000
      threshold_percent = 80
      department_values = ["Engineering", "Development", "DevOps"]
    }
    marketing = {
      amount            = 500
      threshold_percent = 75
      department_values = ["Marketing", "Sales", "Customer Success"]
    }
    operations = {
      amount            = 750
      threshold_percent = 85
      department_values = ["Operations", "Finance", "HR"]
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.department_budgets : v.amount > 0 && v.threshold_percent > 0 && v.threshold_percent <= 100
    ])
    error_message = "Budget amounts must be positive and threshold percentages must be between 1 and 100."
  }
}

variable "cost_anomaly_threshold" {
  description = "Threshold amount for cost anomaly detection in USD"
  type        = number
  default     = 100

  validation {
    condition     = var.cost_anomaly_threshold > 0
    error_message = "Cost anomaly threshold must be a positive number."
  }
}

variable "schedule_expression" {
  description = "Cron expression for cost allocation processing schedule"
  type        = string
  default     = "cron(0 9 1 * ? *)" # First day of month at 9 AM UTC

  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.schedule_expression))
    error_message = "Schedule expression must be a valid cron expression."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "cur_report_versioning" {
  description = "Versioning setting for Cost and Usage Reports"
  type        = string
  default     = "OVERWRITE_REPORT"

  validation {
    condition     = contains(["CREATE_NEW_REPORT", "OVERWRITE_REPORT"], var.cur_report_versioning)
    error_message = "CUR report versioning must be CREATE_NEW_REPORT or OVERWRITE_REPORT."
  }
}

variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection"
  type        = bool
  default     = true
}

variable "s3_lifecycle_rules" {
  description = "S3 lifecycle rules for cost report bucket"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
    expiration_days           = number
  })
  default = {
    transition_to_ia_days      = 30
    transition_to_glacier_days = 90
    expiration_days           = 2555 # 7 years
  }

  validation {
    condition = (
      var.s3_lifecycle_rules.transition_to_ia_days < var.s3_lifecycle_rules.transition_to_glacier_days &&
      var.s3_lifecycle_rules.transition_to_glacier_days < var.s3_lifecycle_rules.expiration_days
    )
    error_message = "Lifecycle rules must be in ascending order: IA < Glacier < Expiration."
  }
}