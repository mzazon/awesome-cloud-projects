# Input variables for Aurora DSQL multi-region disaster recovery infrastructure

variable "primary_region" {
  description = "Primary AWS region for Aurora DSQL cluster deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"
    ], var.primary_region)
    error_message = "Primary region must be a valid AWS region with Aurora DSQL support."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for Aurora DSQL cluster deployment"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid AWS region with Aurora DSQL support."
  }
}

variable "witness_region" {
  description = "Witness AWS region for Aurora DSQL cluster quorum"
  type        = string
  default     = "us-west-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"
    ], var.witness_region)
    error_message = "Witness region must be a valid AWS region with Aurora DSQL support."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "cluster_prefix" {
  description = "Prefix for Aurora DSQL cluster names"
  type        = string
  default     = "dr-dsql"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_prefix))
    error_message = "Cluster prefix must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.lambda_reserved_concurrency >= 1 && var.lambda_reserved_concurrency <= 1000
    error_message = "Lambda reserved concurrency must be between 1 and 1000."
  }
}

variable "monitoring_schedule" {
  description = "EventBridge schedule expression for health monitoring"
  type        = string
  default     = "rate(2 minutes)"
  
  validation {
    condition     = can(regex("^rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)$", var.monitoring_schedule))
    error_message = "Schedule must be a valid EventBridge rate expression (e.g., 'rate(2 minutes)')."
  }
}

variable "cloudwatch_metric_namespace" {
  description = "CloudWatch namespace for custom Aurora DSQL metrics"
  type        = string
  default     = "Aurora/DSQL/DisasterRecovery"
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarm metrics"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, or 3600 seconds."
  }
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

variable "enable_sns_encryption" {
  description = "Enable server-side encryption for SNS topics"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for all resources"
  type        = bool
  default     = true
}

variable "enable_cross_region_alerts" {
  description = "Enable cross-region alert notifications"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = "Aurora-DSQL-DR-Dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.dashboard_name))
    error_message = "Dashboard name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9_:.-]+$", k)) && can(regex("^[a-zA-Z0-9_:.-\\s]*$", v))])
    error_message = "Tag keys and values must contain only valid characters."
  }
}