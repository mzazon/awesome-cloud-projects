# variables.tf - Input variables for AWS IoT Rules Engine Event Processing

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "temperature_threshold" {
  description = "Temperature threshold in Celsius for triggering alerts"
  type        = number
  default     = 70
  
  validation {
    condition     = var.temperature_threshold > 0 && var.temperature_threshold < 200
    error_message = "Temperature threshold must be between 0 and 200 degrees Celsius."
  }
}

variable "vibration_threshold" {
  description = "Vibration threshold for motor monitoring"
  type        = number
  default     = 5.0
  
  validation {
    condition     = var.vibration_threshold > 0 && var.vibration_threshold < 50
    error_message = "Vibration threshold must be between 0 and 50."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "enable_data_archival" {
  description = "Enable data archival rule for historical analysis"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for SNS alert notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "If provided, alert_email must be a valid email address."
  }
}

variable "create_test_thing" {
  description = "Create IoT Thing and related resources for testing"
  type        = bool
  default     = false
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = false
}

variable "sns_topic_name_override" {
  description = "Override the SNS topic name (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_topic_name_override == "" || can(regex("^[a-zA-Z0-9_-]+$", var.sns_topic_name_override))
    error_message = "SNS topic name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "dynamodb_table_name_override" {
  description = "Override the DynamoDB table name (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.dynamodb_table_name_override == "" || can(regex("^[a-zA-Z0-9_.-]+$", var.dynamodb_table_name_override))
    error_message = "DynamoDB table name must contain only alphanumeric characters, hyphens, underscores, and dots."
  }
}

variable "iot_rules_logging_level" {
  description = "Logging level for IoT Rules Engine"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.iot_rules_logging_level)
    error_message = "IoT Rules logging level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (optional)"
  type        = number
  default     = null
  
  validation {
    condition     = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Lambda reserved concurrency must be between 0 and 1000."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for alarm evaluation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods > 0 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "sns_subscription_protocols" {
  description = "Additional SNS subscription protocols and endpoints"
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for sub in var.sns_subscription_protocols : 
      contains(["email", "email-json", "sms", "sqs", "lambda", "http", "https"], sub.protocol)
    ])
    error_message = "SNS subscription protocol must be one of: email, email-json, sms, sqs, lambda, http, https."
  }
}

variable "security_event_types" {
  description = "List of security event types to monitor"
  type        = list(string)
  default     = ["intrusion", "unauthorized_access", "door_breach"]
  
  validation {
    condition     = length(var.security_event_types) > 0
    error_message = "At least one security event type must be specified."
  }
}

variable "motor_status_conditions" {
  description = "Conditions for motor status monitoring"
  type = object({
    error_status    = string
    vibration_threshold = number
  })
  default = {
    error_status    = "error"
    vibration_threshold = 5.0
  }
}

variable "data_archival_interval" {
  description = "Data archival interval in seconds (300 = 5 minutes)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.data_archival_interval > 0 && var.data_archival_interval <= 3600
    error_message = "Data archival interval must be between 1 and 3600 seconds."
  }
}