# Variables for Infrastructure Management Automation
# This file defines all configurable parameters for the infrastructure

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "infra-automation"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must be 20 characters or less and contain only alphanumeric characters and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = null # Uses provider default region
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
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

variable "schedule_expression" {
  description = "EventBridge schedule expression for automation execution"
  type        = string
  default     = "cron(0 6 * * ? *)" # Daily at 6 AM UTC
  
  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.schedule_expression))
    error_message = "Schedule expression must be a valid EventBridge cron or rate expression."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}

variable "notification_email" {
  description = "Email address for automation notifications (leave empty to skip SNS setup)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "enable_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "Infrastructure Automation"
    Terraform = "true"
  }
}

# Local values for computed configurations
locals {
  # Generate unique suffix for resource names
  resource_suffix = random_id.suffix.hex
  
  # Combine project name with suffix for unique resource naming
  name_prefix = "${var.project_name}-${local.resource_suffix}"
  
  # Common tags merged with user-defined tags
  common_tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Region      = data.aws_region.current.name
      CreatedBy   = "Terraform"
      CreatedAt   = formatdate("YYYY-MM-DD", timestamp())
    }
  )
  
  # Lambda function configuration
  lambda_function_name = "InfrastructureAutomation-${local.resource_suffix}"
  automation_role_name = "InfraAutomationRole-${local.resource_suffix}"
  
  # CloudWatch configuration
  log_group_name = "/aws/automation/infrastructure-health"
  dashboard_name = "InfrastructureAutomation-${local.resource_suffix}"
  
  # EventBridge configuration
  schedule_rule_name = "InfrastructureHealthSchedule-${local.resource_suffix}"
  
  # SNS configuration
  sns_topic_name = "automation-alerts-${local.resource_suffix}"
  
  # Systems Manager configuration
  automation_document_name = "InfrastructureHealthCheck-${local.resource_suffix}"
}