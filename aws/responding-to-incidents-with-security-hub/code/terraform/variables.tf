# Input Variables for Security Incident Response with AWS Security Hub
# These variables allow customization of the deployment for different environments

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "notification_email" {
  description = "Email address for security incident notifications"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "security-hub"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_security_standards" {
  description = "Enable AWS Security Hub default security standards"
  type        = bool
  default     = true
}

variable "enable_cis_benchmark" {
  description = "Enable CIS AWS Foundations Benchmark standard"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "sns_delivery_retry_policy" {
  description = "SNS delivery retry policy configuration"
  type = object({
    num_retries         = number
    min_delay_target    = number
    max_delay_target    = number
    backoff_function    = string
  })
  default = {
    num_retries         = 3
    min_delay_target    = 20
    max_delay_target    = 20
    backoff_function    = "linear"
  }
}

variable "sqs_message_retention_period" {
  description = "SQS message retention period in seconds (1-14 days)"
  type        = number
  default     = 1209600  # 14 days

  validation {
    condition     = var.sqs_message_retention_period >= 60 && var.sqs_message_retention_period <= 1209600
    error_message = "SQS message retention period must be between 60 seconds and 1209600 seconds (14 days)."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_threat_intelligence" {
  description = "Enable threat intelligence Lambda function"
  type        = bool
  default     = true
}

variable "create_custom_action" {
  description = "Create Security Hub custom action for manual escalation"
  type        = bool
  default     = true
}

variable "automation_rules_enabled" {
  description = "Enable Security Hub automation rules"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "severity_filter" {
  description = "List of severity levels to process (CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL)"
  type        = list(string)
  default     = ["CRITICAL", "HIGH"]

  validation {
    condition = alltrue([
      for s in var.severity_filter : contains(["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL"], s)
    ])
    error_message = "Severity filter must contain only valid severity levels: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}