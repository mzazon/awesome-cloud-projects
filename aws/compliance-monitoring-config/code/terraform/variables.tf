# Variables for AWS Config Compliance Monitoring Infrastructure
# This file defines all configurable parameters for the compliance monitoring solution

variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "config-compliance"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

variable "config_delivery_frequency" {
  description = "Frequency for Config snapshot delivery"
  type        = string
  default     = "TwentyFour_Hours"
  
  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Delivery frequency must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}

variable "enable_global_resource_recording" {
  description = "Whether to record global resources like IAM"
  type        = bool
  default     = true
}

variable "enable_all_resource_recording" {
  description = "Whether to record all supported resource types"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for compliance notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "required_tags" {
  description = "Required tags for EC2 instances"
  type        = map(string)
  default = {
    Environment = "Required"
    Owner       = "Required"
  }
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

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_retention_days)
    error_message = "Retention days must be one of the valid CloudWatch retention periods."
  }
}

variable "enable_remediation" {
  description = "Whether to enable automatic remediation"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for CloudWatch alarm evaluation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AWS-Config-Compliance"
    ManagedBy   = "Terraform"
    Purpose     = "Compliance-Monitoring"
  }
}