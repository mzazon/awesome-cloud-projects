# =============================================================================
# VARIABLES - AUTOMATED SECURITY SCANNING WITH INSPECTOR AND SECURITY HUB
# =============================================================================
# This file contains all the configurable variables for the automated security
# scanning solution with comprehensive input validation and documentation.
# =============================================================================

# -----------------------------------------------------------------------------
# GENERAL CONFIGURATION
# -----------------------------------------------------------------------------

variable "resource_prefix" {
  description = "Prefix to be used for all resource names to ensure uniqueness and easy identification"
  type        = string
  default     = "automated-security"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix)) && length(var.resource_prefix) <= 30
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens, and be 30 characters or less."
  }
}

variable "common_tags" {
  description = "Common tags to be applied to all resources for consistent resource management and cost tracking"
  type        = map(string)
  default = {
    Project     = "AutomatedSecurityScanning"
    Environment = "Production"
    Owner       = "SecurityTeam"
    CreatedBy   = "Terraform"
    CostCenter  = "Security"
  }
}

# -----------------------------------------------------------------------------
# SECURITY HUB CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_default_standards" {
  description = "Whether to enable default security standards in AWS Security Hub"
  type        = bool
  default     = true
}

variable "enable_organization_management" {
  description = "Whether to enable organization-level management for Security Hub and Inspector (requires AWS Organizations)"
  type        = bool
  default     = false
}

variable "enable_cis_benchmark" {
  description = "Whether to enable CIS AWS Foundations Benchmark standard in Security Hub"
  type        = bool
  default     = true
}

variable "enable_aws_foundational_standard" {
  description = "Whether to enable AWS Foundational Security Best Practices standard in Security Hub"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# AMAZON INSPECTOR CONFIGURATION
# -----------------------------------------------------------------------------

variable "inspector_resource_types" {
  description = "List of resource types to enable for Amazon Inspector scanning"
  type        = list(string)
  default     = ["EC2", "ECR", "LAMBDA"]

  validation {
    condition = alltrue([
      for resource_type in var.inspector_resource_types :
      contains(["EC2", "ECR", "LAMBDA"], resource_type)
    ])
    error_message = "Inspector resource types must be one of: EC2, ECR, LAMBDA."
  }
}

variable "inspector_scan_mode" {
  description = "Scanning mode for Amazon Inspector EC2 instances (EC2_SSM_AGENT_BASED or EC2_HYBRID)"
  type        = string
  default     = "EC2_HYBRID"

  validation {
    condition     = contains(["EC2_SSM_AGENT_BASED", "EC2_HYBRID"], var.inspector_scan_mode)
    error_message = "Inspector scan mode must be either EC2_SSM_AGENT_BASED or EC2_HYBRID."
  }
}

variable "ecr_rescan_duration" {
  description = "Duration for ECR repository rescanning (LIFETIME, DAYS_30, DAYS_14, DAYS_1)"
  type        = string
  default     = "DAYS_30"

  validation {
    condition     = contains(["LIFETIME", "DAYS_30", "DAYS_14", "DAYS_1"], var.ecr_rescan_duration)
    error_message = "ECR rescan duration must be one of: LIFETIME, DAYS_30, DAYS_14, DAYS_1."
  }
}

# -----------------------------------------------------------------------------
# NOTIFICATION CONFIGURATION
# -----------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address to receive security alert notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "alert_severity_levels" {
  description = "List of severity levels that should trigger automated alerts and responses"
  type        = list(string)
  default     = ["HIGH", "CRITICAL"]

  validation {
    condition = alltrue([
      for severity in var.alert_severity_levels :
      contains(["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"], severity)
    ])
    error_message = "Alert severity levels must be one of: INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "enable_sns_encryption" {
  description = "Whether to enable server-side encryption for SNS topic"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LAMBDA FUNCTION CONFIGURATION
# -----------------------------------------------------------------------------

variable "lambda_runtime" {
  description = "Runtime version for Lambda functions"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs in CloudWatch"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Lambda log retention days must be a valid CloudWatch Logs retention period."
  }
}

# -----------------------------------------------------------------------------
# COMPLIANCE REPORTING CONFIGURATION
# -----------------------------------------------------------------------------

variable "compliance_report_schedule" {
  description = "Schedule expression for automated compliance reporting (EventBridge schedule format)"
  type        = string
  default     = "rate(7 days)"

  validation {
    condition     = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.compliance_report_schedule))
    error_message = "Compliance report schedule must be a valid EventBridge schedule expression."
  }
}

variable "compliance_reports_retention_days" {
  description = "Number of days to retain compliance reports in S3"
  type        = number
  default     = 365

  validation {
    condition     = var.compliance_reports_retention_days >= 30 && var.compliance_reports_retention_days <= 2555
    error_message = "Compliance reports retention must be between 30 and 2555 days."
  }
}

variable "enable_compliance_report_encryption" {
  description = "Whether to enable server-side encryption for compliance reports S3 bucket"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# TEST INSTANCE CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_test_instance" {
  description = "Whether to create a test EC2 instance for vulnerability scanning demonstration"
  type        = bool
  default     = false
}

variable "test_instance_type" {
  description = "EC2 instance type for the test instance"
  type        = string
  default     = "t3.micro"

  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.[a-z0-9]+$", var.test_instance_type))
    error_message = "Test instance type must be a valid EC2 instance type format."
  }
}

variable "test_instance_key_pair" {
  description = "Name of the EC2 Key Pair to use for the test instance (leave empty to create without key pair)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# EVENTBRIDGE CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_eventbridge_dead_letter_queue" {
  description = "Whether to enable dead letter queue for EventBridge rules"
  type        = bool
  default     = true
}

variable "eventbridge_retry_policy_maximum_retry_attempts" {
  description = "Maximum number of retry attempts for EventBridge rule targets"
  type        = number
  default     = 3

  validation {
    condition     = var.eventbridge_retry_policy_maximum_retry_attempts >= 0 && var.eventbridge_retry_policy_maximum_retry_attempts <= 185
    error_message = "EventBridge maximum retry attempts must be between 0 and 185."
  }
}

variable "eventbridge_retry_policy_maximum_event_age" {
  description = "Maximum age of events in seconds before they are discarded"
  type        = number
  default     = 3600

  validation {
    condition     = var.eventbridge_retry_policy_maximum_event_age >= 60 && var.eventbridge_retry_policy_maximum_event_age <= 86400
    error_message = "EventBridge maximum event age must be between 60 and 86400 seconds."
  }
}

# -----------------------------------------------------------------------------
# CLOUDWATCH CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for security monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1 && var.cloudwatch_alarm_evaluation_periods <= 100
    error_message = "CloudWatch alarm evaluation periods must be between 1 and 100."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarms (number of errors before alarm triggers)"
  type        = number
  default     = 5

  validation {
    condition     = var.cloudwatch_alarm_threshold >= 1
    error_message = "CloudWatch alarm threshold must be at least 1."
  }
}

# -----------------------------------------------------------------------------
# SECURITY AND NETWORKING
# -----------------------------------------------------------------------------

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access test resources (only used if create_test_instance is true)"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks :
      can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}

variable "vpc_id" {
  description = "VPC ID where resources will be created (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID where EC2 instances will be created (leave empty to use default subnet)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# COST OPTIMIZATION
# -----------------------------------------------------------------------------

variable "enable_cost_allocation_tags" {
  description = "Whether to enable detailed cost allocation tags for cost tracking and optimization"
  type        = bool
  default     = true
}

variable "lifecycle_rule_enabled" {
  description = "Whether to enable S3 lifecycle rules for cost optimization"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Number of days after which objects transition to S3 Infrequent Access"
  type        = number
  default     = 30

  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days after which objects transition to S3 Glacier"
  type        = number
  default     = 90

  validation {
    condition     = var.transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

# -----------------------------------------------------------------------------
# ADVANCED CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_enhanced_monitoring" {
  description = "Whether to enable enhanced monitoring and detailed metrics"
  type        = bool
  default     = false
}

variable "inspector_findings_filter" {
  description = "Additional filters for Inspector findings processing"
  type = object({
    min_cvss_score    = optional(number, 7.0)
    package_names     = optional(list(string), [])
    vulnerability_ids = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = var.inspector_findings_filter.min_cvss_score >= 0.0 && var.inspector_findings_filter.min_cvss_score <= 10.0
    error_message = "Minimum CVSS score must be between 0.0 and 10.0."
  }
}

variable "custom_insights" {
  description = "Custom Security Hub insights to create"
  type = list(object({
    name              = string
    group_by_attribute = string
    filters = object({
      severity_labels    = optional(list(string), [])
      resource_types     = optional(list(string), [])
      compliance_status  = optional(list(string), [])
      record_states      = optional(list(string), [])
    })
  }))
  default = []
}

variable "auto_remediation_enabled" {
  description = "Whether to enable automatic remediation for certain finding types"
  type        = bool
  default     = false
}

variable "auto_remediation_actions" {
  description = "Configuration for automatic remediation actions"
  type = object({
    tag_non_compliant_resources = optional(bool, true)
    create_jira_tickets        = optional(bool, false)
    send_slack_notifications   = optional(bool, false)
    quarantine_instances       = optional(bool, false)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# INTEGRATION CONFIGURATION
# -----------------------------------------------------------------------------

variable "external_integrations" {
  description = "Configuration for external system integrations"
  type = object({
    jira_webhook_url    = optional(string, "")
    slack_webhook_url   = optional(string, "")
    splunk_hec_endpoint = optional(string, "")
    siem_integration    = optional(bool, false)
  })
  default = {}

  validation {
    condition = alltrue([
      var.external_integrations.jira_webhook_url == "" || can(regex("^https://", var.external_integrations.jira_webhook_url)),
      var.external_integrations.slack_webhook_url == "" || can(regex("^https://", var.external_integrations.slack_webhook_url)),
      var.external_integrations.splunk_hec_endpoint == "" || can(regex("^https://", var.external_integrations.splunk_hec_endpoint))
    ])
    error_message = "All webhook URLs must be valid HTTPS URLs or empty strings."
  }
}