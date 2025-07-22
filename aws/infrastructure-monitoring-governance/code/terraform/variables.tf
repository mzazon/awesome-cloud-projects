# Variables for Infrastructure Monitoring with CloudTrail, Config, and Systems Manager

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = null
  
  validation {
    condition = var.aws_region == null || can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_automated_remediation" {
  description = "Enable automated remediation using Lambda functions for Config rule violations"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address to receive notifications from SNS topic (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "cloudtrail_enable_insights" {
  description = "Enable CloudTrail Insights for anomalous activity detection"
  type        = bool
  default     = false
}

variable "config_recorder_name" {
  description = "Name for the AWS Config configuration recorder"
  type        = string
  default     = "default"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.config_recorder_name))
    error_message = "Config recorder name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "config_delivery_channel_name" {
  description = "Name for the AWS Config delivery channel"
  type        = string
  default     = "default"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.config_delivery_channel_name))
    error_message = "Config delivery channel name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "s3_bucket_lifecycle_enabled" {
  description = "Enable S3 bucket lifecycle configuration for cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days after which objects transition to Infrequent Access storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days after which objects transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the supported values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "maintenance_window_schedule" {
  description = "Cron expression for Systems Manager maintenance window schedule"
  type        = string
  default     = "cron(0 02 ? * SUN *)"
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.maintenance_window_schedule))
    error_message = "Maintenance window schedule must be a valid cron expression."
  }
}

variable "maintenance_window_duration" {
  description = "Duration of the maintenance window in hours"
  type        = number
  default     = 4
  
  validation {
    condition     = var.maintenance_window_duration >= 1 && var.maintenance_window_duration <= 24
    error_message = "Maintenance window duration must be between 1 and 24 hours."
  }
}

variable "maintenance_window_cutoff" {
  description = "Number of hours before the end of the maintenance window that Systems Manager stops scheduling new tasks"
  type        = number
  default     = 1
  
  validation {
    condition     = var.maintenance_window_cutoff >= 0 && var.maintenance_window_cutoff <= 23
    error_message = "Maintenance window cutoff must be between 0 and 23 hours."
  }
}

variable "enable_config_rules" {
  description = "Map of Config rules to enable"
  type = object({
    s3_bucket_public_access_prohibited = bool
    encrypted_volumes                  = bool
    root_access_key_check             = bool
    iam_password_policy               = bool
  })
  default = {
    s3_bucket_public_access_prohibited = true
    encrypted_volumes                  = true
    root_access_key_check             = true
    iam_password_policy               = true
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda remediation function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda remediation function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda remediation function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : 
      can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", key)) && 
      can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", value))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_widgets_config" {
  description = "Configuration for dashboard widgets"
  type = object({
    compliance_widget_width  = number
    compliance_widget_height = number
    logs_widget_width       = number
    logs_widget_height      = number
  })
  default = {
    compliance_widget_width  = 12
    compliance_widget_height = 6
    logs_widget_width       = 24
    logs_widget_height      = 6
  }
  
  validation {
    condition = (
      var.dashboard_widgets_config.compliance_widget_width >= 1 && var.dashboard_widgets_config.compliance_widget_width <= 24 &&
      var.dashboard_widgets_config.compliance_widget_height >= 1 && var.dashboard_widgets_config.compliance_widget_height <= 1000 &&
      var.dashboard_widgets_config.logs_widget_width >= 1 && var.dashboard_widgets_config.logs_widget_width <= 24 &&
      var.dashboard_widgets_config.logs_widget_height >= 1 && var.dashboard_widgets_config.logs_widget_height <= 1000
    )
    error_message = "Widget dimensions must be within valid ranges (width: 1-24, height: 1-1000)."
  }
}