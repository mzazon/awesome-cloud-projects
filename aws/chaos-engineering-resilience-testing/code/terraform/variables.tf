# Input variables for the AWS FIS and EventBridge chaos engineering solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "test"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "notification_email" {
  description = "Email address for SNS notifications from chaos experiments"
  type        = string
  default     = "your-email@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Email address must be valid."
  }
}

variable "experiment_schedule" {
  description = "Cron expression for automated experiment execution (default: daily at 2 AM UTC)"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "cpu_stress_duration" {
  description = "Duration for CPU stress test in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.cpu_stress_duration >= 60 && var.cpu_stress_duration <= 600
    error_message = "CPU stress duration must be between 60 and 600 seconds."
  }
}

variable "cpu_load_percent" {
  description = "CPU load percentage for stress test"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_load_percent >= 50 && var.cpu_load_percent <= 100
    error_message = "CPU load percentage must be between 50 and 100."
  }
}

variable "error_rate_threshold" {
  description = "Error rate threshold for experiment stop condition"
  type        = number
  default     = 50
}

variable "high_cpu_threshold" {
  description = "CPU utilization threshold for monitoring alarm"
  type        = number
  default     = 90
  
  validation {
    condition     = var.high_cpu_threshold >= 70 && var.high_cpu_threshold <= 100
    error_message = "CPU threshold must be between 70 and 100 percent."
  }
}

variable "enable_automated_schedule" {
  description = "Whether to enable automated experiment scheduling"
  type        = bool
  default     = false
}

variable "target_instance_tags" {
  description = "Tags to identify target EC2 instances for chaos experiments"
  type        = map(string)
  default = {
    ChaosReady = "true"
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "chaos-eng"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only alphanumeric characters and hyphens."
  }
}