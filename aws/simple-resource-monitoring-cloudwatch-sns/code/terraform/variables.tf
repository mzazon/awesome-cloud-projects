# Input Variables for Simple Resource Monitoring with CloudWatch and SNS
# These variables allow customization of the monitoring infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "The AWS region must be a valid region format (e.g., us-west-2, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "email_address" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string

  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email_address))
    error_message = "Please provide a valid email address."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the monitoring demo"
  type        = string
  default     = "t2.micro"

  validation {
    condition = contains([
      "t2.micro", "t2.small", "t2.medium",
      "t3.micro", "t3.small", "t3.medium",
      "t3a.micro", "t3a.small", "t3a.medium"
    ], var.instance_type)
    error_message = "Instance type must be a valid free-tier eligible or small instance type."
  }
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold percentage that triggers the alarm"
  type        = number
  default     = 70

  validation {
    condition = var.cpu_alarm_threshold >= 10 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 10 and 100 percent."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 2

  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "metric_period" {
  description = "Period in seconds over which the specified statistic is applied"
  type        = number
  default     = 300

  validation {
    condition = contains([60, 120, 180, 240, 300, 600, 900, 1800, 3600], var.metric_period)
    error_message = "Metric period must be a valid CloudWatch period (60, 120, 180, 240, 300, 600, 900, 1800, or 3600 seconds)."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for the EC2 instance (1-minute metrics)"
  type        = bool
  default     = false
}

variable "create_key_pair" {
  description = "Whether to create a new key pair for the EC2 instance"
  type        = bool
  default     = false
}

variable "public_key" {
  description = "Public key for SSH access to the instance. Required if create_key_pair is true"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the instance via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All items in allowed_cidr_blocks must be valid CIDR blocks."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "monitoring-demo"

  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.resource_name_prefix))
    error_message = "Resource name prefix can only contain alphanumeric characters and hyphens."
  }
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use the default VPC"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC if creating a new one"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "enable_sns_encryption" {
  description = "Enable server-side encryption for SNS topic"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}