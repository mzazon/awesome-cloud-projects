# Variables for AWS Service Quota Monitoring Infrastructure
# This file defines all configurable parameters for the monitoring solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "notification_email" {
  description = "Email address to receive quota alert notifications"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "quota_threshold_percentage" {
  description = "Percentage threshold for quota utilization alerts (0-100)"
  type        = number
  default     = 80

  validation {
    condition     = var.quota_threshold_percentage >= 50 && var.quota_threshold_percentage <= 100
    error_message = "Quota threshold must be between 50 and 100 percent."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to threshold"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Evaluation periods must be between 1 and 10."
  }
}

variable "alarm_datapoints_to_alarm" {
  description = "Number of datapoints within evaluation period that must breach threshold"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_datapoints_to_alarm >= 1 && var.alarm_datapoints_to_alarm <= var.alarm_evaluation_periods
    error_message = "Datapoints to alarm must be between 1 and evaluation_periods."
  }
}

variable "metric_period_seconds" {
  description = "Period in seconds for CloudWatch metric evaluation"
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.metric_period_seconds)
    error_message = "Metric period must be one of: 60, 300, 900, or 3600 seconds."
  }
}

variable "enable_test_alarms" {
  description = "Whether to create test alarms for validation purposes"
  type        = bool
  default     = false
}

variable "monitored_services" {
  description = "List of AWS services and their quotas to monitor"
  type = map(object({
    service_code   = string
    quota_code     = string
    quota_name     = string
    alarm_name     = string
    description    = string
  }))
  
  default = {
    ec2_instances = {
      service_code = "ec2"
      quota_code   = "L-1216C47A"
      quota_name   = "Running On-Demand EC2 Instances"
      alarm_name   = "EC2-Running-Instances-Quota-Alert"
      description  = "Alert when EC2 running instances exceed threshold"
    }
    vpc_count = {
      service_code = "vpc"
      quota_code   = "L-F678F1CE"
      quota_name   = "VPCs per Region"
      alarm_name   = "VPC-Quota-Alert"
      description  = "Alert when VPC count exceeds threshold"
    }
    lambda_concurrent = {
      service_code = "lambda"
      quota_code   = "L-B99A9384"
      quota_name   = "Concurrent Executions"
      alarm_name   = "Lambda-Concurrent-Executions-Quota-Alert"
      description  = "Alert when Lambda concurrent executions exceed threshold"
    }
  }
}

variable "sns_topic_name_prefix" {
  description = "Prefix for SNS topic name (suffix will be auto-generated)"
  type        = string
  default     = "service-quota-alerts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.sns_topic_name_prefix))
    error_message = "SNS topic prefix can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "additional_notification_endpoints" {
  description = "Additional notification endpoints for quota alerts"
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default = []

  validation {
    condition = alltrue([
      for endpoint in var.additional_notification_endpoints :
      contains(["email", "sms", "http", "https", "sqs", "lambda"], endpoint.protocol)
    ])
    error_message = "Protocol must be one of: email, sms, http, https, sqs, lambda."
  }
}

variable "enable_alarm_actions" {
  description = "Enable alarm actions (notifications). Set to false for testing."
  type        = bool
  default     = true
}

variable "treat_missing_data" {
  description = "How to treat missing data points in alarms"
  type        = string
  default     = "notBreaching"

  validation {
    condition     = contains(["breaching", "notBreaching", "ignore", "missing"], var.treat_missing_data)
    error_message = "Treat missing data must be one of: breaching, notBreaching, ignore, missing."
  }
}