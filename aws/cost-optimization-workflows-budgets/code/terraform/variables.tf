# Variables for AWS Cost Optimization Hub and Budgets Infrastructure
# This file defines all configurable parameters for the cost optimization solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1'."
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

variable "owner" {
  description = "Owner of the resources for tagging and cost allocation"
  type        = string
  default     = "cost-optimization-team"
}

variable "notification_email" {
  description = "Email address to receive budget and cost optimization notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

variable "monthly_budget_threshold" {
  description = "Percentage threshold for budget alerts (1-100)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.monthly_budget_threshold > 0 && var.monthly_budget_threshold <= 100
    error_message = "Budget threshold must be between 1 and 100."
  }
}

variable "ec2_usage_budget_hours" {
  description = "Monthly EC2 usage budget in hours"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.ec2_usage_budget_hours > 0
    error_message = "EC2 usage budget hours must be greater than 0."
  }
}

variable "ri_utilization_threshold" {
  description = "Reserved Instance utilization threshold percentage"
  type        = number
  default     = 80
  
  validation {
    condition     = var.ri_utilization_threshold > 0 && var.ri_utilization_threshold <= 100
    error_message = "RI utilization threshold must be between 1 and 100."
  }
}

variable "anomaly_detection_threshold" {
  description = "Cost anomaly detection threshold in USD"
  type        = number
  default     = 100
  
  validation {
    condition     = var.anomaly_detection_threshold > 0
    error_message = "Anomaly detection threshold must be greater than 0."
  }
}

variable "enable_budget_actions" {
  description = "Enable automated budget actions when thresholds are exceeded"
  type        = bool
  default     = false
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "cost_optimization_hub_enabled" {
  description = "Enable Cost Optimization Hub preferences"
  type        = bool
  default     = true
}

variable "savings_estimation_mode" {
  description = "Savings estimation mode for Cost Optimization Hub"
  type        = string
  default     = "AFTER_DISCOUNTS"
  
  validation {
    condition     = contains(["AFTER_DISCOUNTS", "BEFORE_DISCOUNTS"], var.savings_estimation_mode)
    error_message = "Savings estimation mode must be AFTER_DISCOUNTS or BEFORE_DISCOUNTS."
  }
}

variable "member_account_discount_visibility" {
  description = "Member account discount visibility for Cost Optimization Hub"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["ALL", "STANDARD", "NONE"], var.member_account_discount_visibility)
    error_message = "Member account discount visibility must be ALL, STANDARD, or NONE."
  }
}

variable "monitored_services" {
  description = "List of AWS services to monitor for cost anomalies"
  type        = list(string)
  default = [
    "EC2-Instance",
    "RDS",
    "S3",
    "Lambda"
  ]
}