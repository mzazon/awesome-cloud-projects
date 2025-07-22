# ==========================================
# Input Variables for Cost Anomaly Detection
# ==========================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cost-anomaly-detection"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "email_address" {
  description = "Email address for cost anomaly notifications"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email_address))
    error_message = "Email address must be a valid email format."
  }
}

variable "anomaly_threshold" {
  description = "Cost anomaly detection threshold in dollars"
  type        = number
  default     = 10.0

  validation {
    condition     = var.anomaly_threshold >= 0
    error_message = "Anomaly threshold must be a positive number."
  }
}

variable "detection_frequency" {
  description = "Frequency for anomaly detection notifications (IMMEDIATE or DAILY)"
  type        = string
  default     = "IMMEDIATE"

  validation {
    condition     = contains(["IMMEDIATE", "DAILY"], var.detection_frequency)
    error_message = "Detection frequency must be either IMMEDIATE or DAILY."
  }
}

variable "monitor_dimension" {
  description = "Dimension to monitor for cost anomalies (SERVICE, LINKED_ACCOUNT, etc.)"
  type        = string
  default     = "SERVICE"

  validation {
    condition = contains([
      "SERVICE",
      "LINKED_ACCOUNT",
      "USAGE_TYPE",
      "REGION",
      "INSTANCE_TYPE",
      "BILLING_ENTITY",
      "PLATFORM",
      "PURCHASE_TYPE",
      "RESERVATION_ID",
      "SAVINGS_PLANS_TYPE",
      "SAVINGS_PLAN_ARN",
      "OPERATING_SYSTEM",
      "TENANCY",
      "SCOPE",
      "CATEGORY",
      "RESOURCE_ID",
      "RIGHTSIZING_TYPE",
      "API_OPERATION",
      "SERVICE_CODE",
      "ENDPOINT_TYPE",
      "BRANCH",
      "INSTANCE_TYPE_FAMILY"
    ], var.monitor_dimension)
    error_message = "Monitor dimension must be a valid AWS Cost Explorer dimension."
  }
}

variable "monitored_services" {
  description = "List of AWS services to monitor for cost anomalies"
  type        = list(string)
  default     = ["Amazon Elastic Compute Cloud - Compute"]

  validation {
    condition     = length(var.monitored_services) > 0
    error_message = "At least one service must be specified for monitoring."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
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

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "additional_sns_endpoints" {
  description = "Additional SNS endpoints for notifications (e.g., phone numbers for SMS)"
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default = []

  validation {
    condition = alltrue([
      for endpoint in var.additional_sns_endpoints : 
      contains(["email", "sms", "http", "https", "lambda", "sqs"], endpoint.protocol)
    ])
    error_message = "SNS endpoint protocols must be one of: email, sms, http, https, lambda, sqs."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}