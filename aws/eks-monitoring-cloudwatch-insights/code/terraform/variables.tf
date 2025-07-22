# Input variables for EKS CloudWatch Container Insights deployment
# These variables allow customization of the monitoring solution

variable "cluster_name" {
  description = "Name of the existing EKS cluster to monitor"
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0 && length(var.cluster_name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "aws_region" {
  description = "AWS region where the EKS cluster is deployed"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "notification_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string

  validation {
    condition     = can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "enable_control_plane_logging" {
  description = "Enable comprehensive EKS control plane logging"
  type        = bool
  default     = true
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold percentage for CloudWatch alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 1 and 100."
  }
}

variable "memory_alarm_threshold" {
  description = "Memory utilization threshold percentage for CloudWatch alarm"
  type        = number
  default     = 85

  validation {
    condition     = var.memory_alarm_threshold > 0 && var.memory_alarm_threshold <= 100
    error_message = "Memory alarm threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "cloudwatch_agent_image" {
  description = "CloudWatch Agent container image to use"
  type        = string
  default     = "amazon/cloudwatch-agent:1.300032.2b249"
}

variable "fluent_bit_image" {
  description = "Fluent Bit container image to use for log collection"
  type        = string
  default     = "fluent/fluent-bit:2.1.10"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}