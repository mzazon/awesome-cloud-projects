# Variables for AWS Systems Manager State Manager configuration management infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "notification_email" {
  description = "Email address for configuration drift notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "association_schedule" {
  description = "Schedule expression for State Manager associations (rate or cron)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.association_schedule))
    error_message = "Schedule must be a valid rate() or cron() expression."
  }
}

variable "agent_update_schedule" {
  description = "Schedule expression for SSM Agent updates"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.agent_update_schedule))
    error_message = "Schedule must be a valid rate() or cron() expression."
  }
}

variable "target_tag_key" {
  description = "Tag key for targeting EC2 instances"
  type        = string
  default     = "Environment"
}

variable "target_tag_value" {
  description = "Tag value for targeting EC2 instances"
  type        = string
  default     = "Demo"
}

variable "compliance_severity" {
  description = "Compliance severity level for associations"
  type        = string
  default     = "CRITICAL"
  
  validation {
    condition     = contains(["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL"], var.compliance_severity)
    error_message = "Compliance severity must be one of: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL."
  }
}

variable "enable_firewall" {
  description = "Enable firewall configuration in security document"
  type        = bool
  default     = true
}

variable "disable_root_login" {
  description = "Disable root SSH login in security document"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_period" {
  description = "Period in seconds for CloudWatch alarms"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloudwatch_alarm_period >= 60
    error_message = "CloudWatch alarm period must be at least 60 seconds."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarms"
  type        = number
  default     = 1
  
  validation {
    condition     = var.cloudwatch_alarm_threshold >= 0
    error_message = "CloudWatch alarm threshold must be non-negative."
  }
}

variable "s3_bucket_name" {
  description = "S3 bucket name for State Manager output (optional, will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "create_test_instances" {
  description = "Create test EC2 instances for demonstration"
  type        = bool
  default     = false
}

variable "test_instance_type" {
  description = "Instance type for test instances"
  type        = string
  default     = "t3.micro"
}

variable "test_instance_count" {
  description = "Number of test instances to create"
  type        = number
  default     = 2
  
  validation {
    condition     = var.test_instance_count >= 1 && var.test_instance_count <= 10
    error_message = "Test instance count must be between 1 and 10."
  }
}