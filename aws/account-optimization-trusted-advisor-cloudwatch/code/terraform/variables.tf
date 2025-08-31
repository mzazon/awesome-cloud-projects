# ==============================================================================
# Terraform Variables for AWS Trusted Advisor CloudWatch Monitoring
# ==============================================================================
# This file defines all input variables for the Trusted Advisor monitoring 
# infrastructure, including validation rules and detailed descriptions to 
# ensure proper configuration and deployment.
# ==============================================================================

# ==============================================================================
# Project Configuration Variables
# ==============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming and tagging. This will be used as a prefix for all created resources."
  type        = string
  default     = "trusted-advisor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.project_name))
    error_message = "Project name must be 1-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) used for resource tagging and organization."
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources beyond the standard tags (Project, Environment, ManagedBy, Purpose)."
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9\\s._:/=+\\-@]{1,128}$", key))
    ])
    error_message = "Tag keys must be 1-128 characters and contain only letters, numbers, spaces, and the following characters: . _ : / = + - @"
  }
}

# ==============================================================================
# SNS Configuration Variables
# ==============================================================================

variable "notification_emails" {
  description = <<-EOT
    List of email addresses to receive Trusted Advisor alert notifications. 
    Each email will receive an SNS subscription confirmation that must be accepted 
    before notifications are delivered. Leave empty if you prefer to manage 
    subscriptions manually through the AWS console or CLI.
  EOT
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
  
  validation {
    condition     = length(var.notification_emails) <= 10
    error_message = "Maximum of 10 email addresses are allowed for notifications."
  }
}

variable "sns_kms_key_id" {
  description = <<-EOT
    KMS key ID or ARN for SNS topic encryption. If not provided, AWS managed 
    keys will be used. For enhanced security in production environments, 
    consider using a customer-managed KMS key.
  EOT
  type        = string
  default     = "alias/aws/sns"
  
  validation {
    condition = can(regex("^(alias/[a-zA-Z0-9/_-]+|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}|arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.sns_kms_key_id))
    error_message = "SNS KMS key ID must be a valid KMS key ID, ARN, or alias."
  }
}

variable "send_ok_notifications" {
  description = <<-EOT
    Whether to send notifications when alarms return to OK state after being 
    triggered. Enable this to receive confirmation when issues are resolved, 
    but note that it will increase the number of notifications sent.
  EOT
  type        = bool
  default     = false
}

# ==============================================================================
# CloudWatch Alarm Configuration Variables
# ==============================================================================

variable "alarm_evaluation_period" {
  description = <<-EOT
    The period in seconds over which the specified statistic is applied for 
    CloudWatch alarms. Trusted Advisor metrics are typically updated every 
    few hours, so longer periods (300-3600 seconds) are recommended.
  EOT
  type        = number
  default     = 300
  
  validation {
    condition     = var.alarm_evaluation_period >= 60 && var.alarm_evaluation_period <= 86400
    error_message = "Alarm evaluation period must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
  
  validation {
    condition     = var.alarm_evaluation_period % 60 == 0
    error_message = "Alarm evaluation period must be a multiple of 60 seconds."
  }
}

variable "alarm_evaluation_periods" {
  description = <<-EOT
    The number of periods over which data is compared to the specified threshold 
    before triggering the alarm. A value of 1 provides immediate alerting, 
    while higher values reduce false positives.
  EOT
  type        = number
  default     = 1
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

# ==============================================================================
# Trusted Advisor Check Threshold Variables
# ==============================================================================

variable "cost_optimization_threshold" {
  description = <<-EOT
    Threshold for cost optimization alerts. This represents the number of 
    resources flagged by Trusted Advisor's "Low Utilization Amazon EC2 Instances" 
    check that will trigger an alarm. Set to 1 to alert on any underutilized 
    instances, or higher to reduce alert sensitivity.
  EOT
  type        = number
  default     = 1
  
  validation {
    condition     = var.cost_optimization_threshold >= 1 && var.cost_optimization_threshold <= 100
    error_message = "Cost optimization threshold must be between 1 and 100 resources."
  }
}

variable "security_threshold" {
  description = <<-EOT
    Threshold for security alerts. This represents the number of resources 
    flagged by Trusted Advisor's "Security Groups - Specific Ports Unrestricted" 
    check that will trigger an alarm. Set to 1 for immediate security alerting.
  EOT
  type        = number
  default     = 1
  
  validation {
    condition     = var.security_threshold >= 1 && var.security_threshold <= 50
    error_message = "Security threshold must be between 1 and 50 resources."
  }
}

variable "service_limits_threshold" {
  description = <<-EOT
    Threshold percentage for service limit usage alerts (0-100). When your 
    usage of EC2 On-Demand instances exceeds this percentage of your service 
    quota, an alarm will trigger. Recommended values: 70-90% for proactive 
    planning, 80% is a good balance between early warning and avoiding false alarms.
  EOT
  type        = number
  default     = 80
  
  validation {
    condition     = var.service_limits_threshold >= 50 && var.service_limits_threshold <= 95
    error_message = "Service limits threshold must be between 50% and 95%."
  }
}

# ==============================================================================
# Optional Trusted Advisor Check Variables
# ==============================================================================

variable "enable_iam_key_rotation_alarm" {
  description = <<-EOT
    Whether to create a CloudWatch alarm for the IAM Access Key Rotation check. 
    This alarm will trigger when Trusted Advisor identifies IAM access keys 
    that should be rotated for security best practices.
  EOT
  type        = bool
  default     = false
}

variable "enable_rds_security_alarm" {
  description = <<-EOT
    Whether to create a CloudWatch alarm for the Amazon RDS Security Group 
    Access Risk check. This alarm will trigger when Trusted Advisor identifies 
    RDS instances with security groups that may have excessive access permissions.
  EOT
  type        = bool
  default     = false
}

variable "enable_s3_permissions_alarm" {
  description = <<-EOT
    Whether to create a CloudWatch alarm for the Amazon S3 Bucket Permissions 
    check. This alarm will trigger when Trusted Advisor identifies S3 buckets 
    with potentially overpermissive access policies.
  EOT
  type        = bool
  default     = false
}

# ==============================================================================
# Advanced Configuration Variables
# ==============================================================================

variable "datapoints_to_alarm" {
  description = <<-EOT
    The number of datapoints that must be breaching to trigger the alarm. 
    This must be less than or equal to evaluation_periods. Use this for 
    more sophisticated alarm logic when you want to require multiple 
    consecutive breaches before alerting.
  EOT
  type        = number
  default     = null
  
  validation {
    condition = var.datapoints_to_alarm == null || (
      var.datapoints_to_alarm >= 1 && 
      var.datapoints_to_alarm <= var.alarm_evaluation_periods
    )
    error_message = "Datapoints to alarm must be between 1 and the number of evaluation periods."
  }
}

variable "enable_cross_region_monitoring" {
  description = <<-EOT
    Whether to enable monitoring for other AWS regions in addition to the 
    current region. Note that this is experimental and may require additional 
    configuration. Trusted Advisor publishes all metrics to us-east-1 regardless 
    of where resources are located.
  EOT
  type        = bool
  default     = false
}

# ==============================================================================
# Cost and Resource Management Variables
# ==============================================================================

variable "alarm_auto_scaling" {
  description = <<-EOT
    Whether to automatically adjust alarm thresholds based on your account's 
    historical usage patterns. This is an experimental feature that may 
    require additional Lambda functions and CloudWatch metrics analysis.
  EOT
  type        = bool
  default     = false
}

variable "notification_format" {
  description = <<-EOT
    Format for SNS notifications. Options:
    - 'json': Structured JSON format with detailed alarm information
    - 'text': Human-readable text format for email notifications
    - 'custom': Custom format (requires additional configuration)
  EOT
  type        = string
  default     = "text"
  
  validation {
    condition     = contains(["json", "text", "custom"], var.notification_format)
    error_message = "Notification format must be one of: json, text, custom."
  }
}

# ==============================================================================
# Compliance and Governance Variables
# ==============================================================================

variable "compliance_framework" {
  description = <<-EOT
    Compliance framework alignment for tagging and documentation. This helps 
    organize resources according to your organization's compliance requirements.
    Options: 'none', 'sox', 'pci', 'hipaa', 'iso27001', 'custom'
  EOT
  type        = string
  default     = "none"
  
  validation {
    condition     = contains(["none", "sox", "pci", "hipaa", "iso27001", "custom"], var.compliance_framework)
    error_message = "Compliance framework must be one of: none, sox, pci, hipaa, iso27001, custom."
  }
}

variable "retention_period_days" {
  description = <<-EOT
    Number of days to retain CloudWatch alarm history and SNS message logs. 
    This affects cost and compliance with data retention policies. 
    Set to 0 to use AWS default retention periods.
  EOT
  type        = number
  default     = 90
  
  validation {
    condition     = var.retention_period_days >= 0 && var.retention_period_days <= 3653
    error_message = "Retention period must be between 0 and 3653 days (10 years)."
  }
}