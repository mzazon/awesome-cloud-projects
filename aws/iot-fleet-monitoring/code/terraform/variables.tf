# Variables for IoT Device Fleet Monitoring Infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "fleet_name" {
  description = "Name of the IoT device fleet"
  type        = string
  default     = "iot-fleet"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.fleet_name))
    error_message = "Fleet name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "notification_email" {
  description = "Email address for security notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "device_count" {
  description = "Number of test IoT devices to create"
  type        = number
  default     = 5
  
  validation {
    condition     = var.device_count >= 1 && var.device_count <= 50
    error_message = "Device count must be between 1 and 50."
  }
}

variable "enable_scheduled_audit" {
  description = "Enable daily scheduled audit for compliance monitoring"
  type        = bool
  default     = true
}

variable "audit_frequency" {
  description = "Frequency for scheduled audits (DAILY, WEEKLY, BIWEEKLY, MONTHLY)"
  type        = string
  default     = "DAILY"
  
  validation {
    condition     = can(regex("^(DAILY|WEEKLY|BIWEEKLY|MONTHLY)$", var.audit_frequency))
    error_message = "Audit frequency must be DAILY, WEEKLY, BIWEEKLY, or MONTHLY."
  }
}

variable "security_profile_behaviors" {
  description = "Security profile behaviors and their thresholds"
  type = object({
    authorization_failures_threshold = number
    message_byte_size_threshold     = number
    messages_received_threshold     = number
    messages_sent_threshold         = number
    connection_attempts_threshold   = number
    duration_seconds               = number
  })
  default = {
    authorization_failures_threshold = 5
    message_byte_size_threshold     = 1024
    messages_received_threshold     = 100
    messages_sent_threshold         = 100
    connection_attempts_threshold   = 10
    duration_seconds               = 300
  }
}

variable "cloudwatch_alarm_thresholds" {
  description = "CloudWatch alarm thresholds for monitoring"
  type = object({
    security_violations_threshold = number
    low_connectivity_threshold   = number
    processing_errors_threshold  = number
  })
  default = {
    security_violations_threshold = 5
    low_connectivity_threshold   = 3
    processing_errors_threshold  = 10
  }
}

variable "dashboard_widgets" {
  description = "Configuration for CloudWatch dashboard widgets"
  type = object({
    enable_device_overview     = bool
    enable_security_violations = bool
    enable_message_processing  = bool
    enable_violation_logs      = bool
  })
  default = {
    enable_device_overview     = true
    enable_security_violations = true
    enable_message_processing  = true
    enable_violation_logs      = true
  }
}

variable "lambda_function_config" {
  description = "Lambda function configuration for automated remediation"
  type = object({
    runtime     = string
    timeout     = number
    memory_size = number
  })
  default = {
    runtime     = "python3.9"
    timeout     = 60
    memory_size = 128
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "Backup region for cross-region replication"
  type        = string
  default     = "us-west-2"
}

variable "cost_optimization" {
  description = "Cost optimization settings"
  type = object({
    use_spot_instances     = bool
    enable_lifecycle_rules = bool
    compress_logs         = bool
  })
  default = {
    use_spot_instances     = false
    enable_lifecycle_rules = true
    compress_logs         = true
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}