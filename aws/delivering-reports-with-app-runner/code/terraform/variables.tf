# =============================================================================
# Email Reports Infrastructure - Variables
# =============================================================================
# Variable definitions for configuring the scheduled email reports system.
# These variables allow customization of email addresses, GitHub repository,
# scheduling, and monitoring configurations.

# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "ses_verified_email" {
  description = "Email address that has been verified in Amazon SES for sending emails. This email will be used as both sender and recipient for the reports. Must be verified in SES before deployment."
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.ses_verified_email))
    error_message = "The ses_verified_email must be a valid email address format."
  }
}

variable "github_repository_url" {
  description = "GitHub repository URL containing the Flask application source code. Must be a public repository accessible by App Runner. Format: https://github.com/username/repository-name"
  type        = string
  
  validation {
    condition = can(regex("^https://github\\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", var.github_repository_url))
    error_message = "The github_repository_url must be a valid GitHub repository URL in the format: https://github.com/username/repository-name"
  }
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "schedule_expression" {
  description = "Cron expression for when to run the email reports. Default is daily at 9 AM UTC. Use AWS EventBridge Scheduler cron format."
  type        = string
  default     = "cron(0 9 * * ? *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.schedule_expression))
    error_message = "The schedule_expression must be a valid cron expression starting with 'cron(' and ending with ')'."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the schedule expression. Use standard timezone names (e.g., 'America/New_York', 'Europe/London', 'UTC')."
  type        = string
  default     = "UTC"
}

variable "app_runner_cpu" {
  description = "CPU allocation for App Runner service. Valid values: '0.25 vCPU', '0.5 vCPU', '1 vCPU'"
  type        = string
  default     = "0.25 vCPU"
  
  validation {
    condition = contains(["0.25 vCPU", "0.5 vCPU", "1 vCPU"], var.app_runner_cpu)
    error_message = "The app_runner_cpu must be one of: '0.25 vCPU', '0.5 vCPU', '1 vCPU'."
  }
}

variable "app_runner_memory" {
  description = "Memory allocation for App Runner service. Valid values depend on CPU: 0.25 vCPU allows 0.5-2 GB, 0.5 vCPU allows 1-4 GB, 1 vCPU allows 2-8 GB"
  type        = string
  default     = "0.5 GB"
  
  validation {
    condition = can(regex("^\\d+(\\.\\d+)? GB$", var.app_runner_memory))
    error_message = "The app_runner_memory must be in the format 'X GB' or 'X.X GB'."
  }
}

variable "health_check_path" {
  description = "Path for App Runner health checks. Should return HTTP 200 status when application is healthy."
  type        = string
  default     = "/health"
  
  validation {
    condition = can(regex("^/.*", var.health_check_path))
    error_message = "The health_check_path must start with '/'."
  }
}

variable "health_check_interval" {
  description = "Interval in seconds between health checks (5-300 seconds)"
  type        = number
  default     = 10
  
  validation {
    condition = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "The health_check_interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Timeout in seconds for health check requests (1-20 seconds)"
  type        = number
  default     = 5
  
  validation {
    condition = var.health_check_timeout >= 1 && var.health_check_timeout <= 20
    error_message = "The health_check_timeout must be between 1 and 20 seconds."
  }
}

variable "scheduler_retry_attempts" {
  description = "Maximum number of retry attempts for EventBridge Scheduler when invocation fails (0-5)"
  type        = number
  default     = 3
  
  validation {
    condition = var.scheduler_retry_attempts >= 0 && var.scheduler_retry_attempts <= 5
    error_message = "The scheduler_retry_attempts must be between 0 and 5."
  }
}

variable "scheduler_max_event_age" {
  description = "Maximum age in seconds for events in EventBridge Scheduler before they are discarded (60-86400 seconds)"
  type        = number
  default     = 86400
  
  validation {
    condition = var.scheduler_max_event_age >= 60 && var.scheduler_max_event_age <= 86400
    error_message = "The scheduler_max_event_age must be between 60 and 86400 seconds (1 day)."
  }
}

variable "cloudwatch_alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation (60-86400 seconds, must be multiple of 60)"
  type        = number
  default     = 3600
  
  validation {
    condition = var.cloudwatch_alarm_period >= 60 && var.cloudwatch_alarm_period <= 86400 && var.cloudwatch_alarm_period % 60 == 0
    error_message = "The cloudwatch_alarm_period must be between 60 and 86400 seconds and be a multiple of 60."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarm. Alert when ReportsGenerated metric is less than this value"
  type        = number
  default     = 1
  
  validation {
    condition = var.cloudwatch_alarm_threshold >= 0
    error_message = "The cloudwatch_alarm_threshold must be greater than or equal to 0."
  }
}

# -----------------------------------------------------------------------------
# Tagging Variables
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags to be applied to all resources created by this module"
  type        = map(string)
  default = {
    Project   = "EmailReports"
    ManagedBy = "Terraform"
  }
}

variable "environment" {
  description = "Environment name (e.g., 'dev', 'staging', 'prod') for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.environment))
    error_message = "The environment must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# -----------------------------------------------------------------------------
# Advanced Configuration Variables
# -----------------------------------------------------------------------------

variable "enable_auto_deployments" {
  description = "Enable automatic deployments in App Runner when code changes are pushed to the repository"
  type        = bool
  default     = true
}

variable "github_connection_arn" {
  description = "ARN of the GitHub connection for App Runner. If not provided, App Runner will use public repository access"
  type        = string
  default     = ""
}

variable "source_code_version_type" {
  description = "Type of source code version to deploy. Valid values: 'BRANCH'"
  type        = string
  default     = "BRANCH"
  
  validation {
    condition = contains(["BRANCH"], var.source_code_version_type)
    error_message = "The source_code_version_type must be 'BRANCH'."
  }
}

variable "source_code_version_value" {
  description = "Value for the source code version (branch name, tag, or commit hash)"
  type        = string
  default     = "main"
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable creation of CloudWatch dashboard for monitoring the email reports system"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Enable creation of CloudWatch alarms for monitoring report generation failures"
  type        = bool
  default     = true
}