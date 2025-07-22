# =============================================================================
# Variables for AWS CloudWatch Monitoring Infrastructure
# =============================================================================

# =============================================================================
# Required Variables
# =============================================================================

variable "notification_email" {
  description = "Email address to receive alarm notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

# =============================================================================
# Optional Variables with Defaults
# =============================================================================

variable "sns_topic_name" {
  description = "Name for the SNS topic used for alarm notifications"
  type        = string
  default     = "monitoring-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.sns_topic_name))
    error_message = "SNS topic name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "CloudWatch-Monitoring"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# CloudWatch Alarm Configuration Variables
# =============================================================================

variable "alarm_period" {
  description = "The period in seconds over which the statistic is applied"
  type        = number
  default     = 300
  
  validation {
    condition     = var.alarm_period >= 60
    error_message = "Alarm period must be at least 60 seconds."
  }
}

# =============================================================================
# CPU Utilization Alarm Configuration
# =============================================================================

variable "cpu_threshold" {
  description = "CPU utilization threshold percentage that triggers the alarm"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_threshold > 0 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "cpu_alarm_evaluation_periods" {
  description = "Number of periods over which CPU data is compared to the threshold"
  type        = number
  default     = 2
  
  validation {
    condition     = var.cpu_alarm_evaluation_periods >= 1
    error_message = "CPU alarm evaluation periods must be at least 1."
  }
}

# =============================================================================
# Response Time Alarm Configuration
# =============================================================================

variable "response_time_threshold" {
  description = "Response time threshold in seconds that triggers the alarm"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.response_time_threshold > 0
    error_message = "Response time threshold must be greater than 0."
  }
}

variable "response_time_alarm_evaluation_periods" {
  description = "Number of periods over which response time data is compared to the threshold"
  type        = number
  default     = 3
  
  validation {
    condition     = var.response_time_alarm_evaluation_periods >= 1
    error_message = "Response time alarm evaluation periods must be at least 1."
  }
}

# =============================================================================
# Database Connections Alarm Configuration
# =============================================================================

variable "db_connections_threshold" {
  description = "Database connections threshold that triggers the alarm"
  type        = number
  default     = 80
  
  validation {
    condition     = var.db_connections_threshold > 0
    error_message = "Database connections threshold must be greater than 0."
  }
}

variable "db_connections_alarm_evaluation_periods" {
  description = "Number of periods over which database connections data is compared to the threshold"
  type        = number
  default     = 2
  
  validation {
    condition     = var.db_connections_alarm_evaluation_periods >= 1
    error_message = "Database connections alarm evaluation periods must be at least 1."
  }
}

# =============================================================================
# Feature Flags
# =============================================================================

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring metrics"
  type        = bool
  default     = true
}

# =============================================================================
# Advanced Configuration
# =============================================================================

variable "alarm_actions_enabled" {
  description = "Whether alarm actions are enabled for all alarms"
  type        = bool
  default     = true
}

variable "sns_delivery_policy" {
  description = "Custom SNS delivery policy (optional)"
  type        = map(any)
  default     = null
}

variable "additional_alarm_actions" {
  description = "Additional ARNs to notify when alarms trigger (e.g., Lambda functions, other SNS topics)"
  type        = list(string)
  default     = []
}

variable "alarm_name_prefix" {
  description = "Prefix for alarm names (useful for environment separation)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]*$", var.alarm_name_prefix))
    error_message = "Alarm name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# =============================================================================
# Monitoring Scope Configuration
# =============================================================================

variable "monitor_all_ec2_instances" {
  description = "Whether to monitor all EC2 instances or specific instances"
  type        = bool
  default     = true
}

variable "monitor_all_rds_instances" {
  description = "Whether to monitor all RDS instances or specific instances"
  type        = bool
  default     = true
}

variable "monitor_all_load_balancers" {
  description = "Whether to monitor all Application Load Balancers or specific ones"
  type        = bool
  default     = true
}

variable "specific_ec2_instances" {
  description = "List of specific EC2 instance IDs to monitor (used when monitor_all_ec2_instances is false)"
  type        = list(string)
  default     = []
}

variable "specific_rds_instances" {
  description = "List of specific RDS instance identifiers to monitor (used when monitor_all_rds_instances is false)"
  type        = list(string)
  default     = []
}

variable "specific_load_balancers" {
  description = "List of specific ALB ARNs to monitor (used when monitor_all_load_balancers is false)"
  type        = list(string)
  default     = []
}

# =============================================================================
# Cost Optimization Variables
# =============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instances (additional cost)"
  type        = bool
  default     = false
}

variable "alarm_comparison_operator" {
  description = "Default comparison operator for alarms"
  type        = string
  default     = "GreaterThanThreshold"
  
  validation {
    condition = contains([
      "GreaterThanOrEqualToThreshold",
      "GreaterThanThreshold",
      "LessThanThreshold",
      "LessThanOrEqualToThreshold"
    ], var.alarm_comparison_operator)
    error_message = "Alarm comparison operator must be one of: GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold, LessThanOrEqualToThreshold."
  }
}

variable "treat_missing_data" {
  description = "How to treat missing data points for alarms"
  type        = string
  default     = "notBreaching"
  
  validation {
    condition = contains([
      "breaching",
      "notBreaching",
      "ignore",
      "missing"
    ], var.treat_missing_data)
    error_message = "Treat missing data must be one of: breaching, notBreaching, ignore, missing."
  }
}