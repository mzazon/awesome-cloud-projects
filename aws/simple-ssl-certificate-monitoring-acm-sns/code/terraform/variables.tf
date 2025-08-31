# ==============================================================================
# Variable Definitions for SSL Certificate Monitoring Infrastructure
# ==============================================================================
# This file defines all configurable parameters for the SSL certificate
# monitoring solution using AWS Certificate Manager, CloudWatch, and SNS.
# ==============================================================================

# ==============================================================================
# General Configuration Variables
# ==============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment name must be between 1 and 10 characters."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources for better organization and cost tracking"
  type        = map(string)
  default = {
    Project     = "SSL Certificate Monitoring"
    ManagedBy   = "Terraform"
    Owner       = "Security Team"
    CostCenter  = "Infrastructure"
  }
}

# ==============================================================================
# SNS Configuration Variables
# ==============================================================================

variable "sns_topic_name" {
  description = "Base name for the SNS topic that will receive certificate expiration alerts"
  type        = string
  default     = "ssl-cert-alerts"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9_-]+$", var.sns_topic_name))
    error_message = "SNS topic name can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "notification_email" {
  description = "Email address to receive certificate expiration notifications. Leave empty to skip email subscription."
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address or leave empty to skip email notifications."
  }
}

variable "send_ok_notifications" {
  description = "Whether to send OK notifications when certificate alarms return to normal state"
  type        = bool
  default     = false
}

# ==============================================================================
# Certificate Monitoring Configuration
# ==============================================================================

variable "monitor_existing_certificates" {
  description = "Whether to monitor existing certificates by domain name lookup"
  type        = bool
  default     = false
}

variable "certificate_domain_name" {
  description = "Domain name of existing certificate to monitor (required if monitor_existing_certificates is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.certificate_domain_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.certificate_domain_name))
    error_message = "Please provide a valid domain name (e.g., example.com, subdomain.example.com)."
  }
}

variable "certificate_arns" {
  description = "List of specific certificate ARNs to monitor for expiration"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.certificate_arns : can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[a-f0-9-]+$", arn))
    ])
    error_message = "All certificate ARNs must be valid AWS ACM certificate ARNs."
  }
}

# ==============================================================================
# CloudWatch Alarm Configuration
# ==============================================================================

variable "expiration_threshold_days" {
  description = "Number of days before certificate expiration to trigger alarm (recommended: 30-60 days)"
  type        = number
  default     = 30
  
  validation {
    condition = var.expiration_threshold_days >= 1 && var.expiration_threshold_days <= 365
    error_message = "Expiration threshold must be between 1 and 365 days."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 1
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "alarm_period" {
  description = "The period in seconds over which the specified statistic is applied (86400 = 1 day)"
  type        = number
  default     = 86400
  
  validation {
    condition = contains([60, 300, 900, 3600, 21600, 86400], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600, 21600, or 86400 seconds."
  }
}

# ==============================================================================
# Test Certificate Configuration (Optional)
# ==============================================================================

variable "create_test_certificate" {
  description = "Whether to create a test certificate for demonstration purposes (DNS validation required)"
  type        = bool
  default     = false
}

variable "test_certificate_domain" {
  description = "Domain name for the test certificate (required if create_test_certificate is true)"
  type        = string
  default     = "example.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.test_certificate_domain))
    error_message = "Please provide a valid domain name for the test certificate."
  }
}

variable "test_certificate_sans" {
  description = "List of Subject Alternative Names (SANs) for the test certificate"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for san in var.test_certificate_sans : can(regex("^[a-zA-Z0-9*][a-zA-Z0-9*.-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", san))
    ])
    error_message = "All SANs must be valid domain names or wildcard domains."
  }
}

# ==============================================================================
# Dashboard Configuration (Optional)
# ==============================================================================

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard for certificate monitoring visualization"
  type        = bool
  default     = true
}

# ==============================================================================
# Advanced Configuration Variables
# ==============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for certificate metrics (may incur additional charges)"
  type        = bool
  default     = false
}

variable "alarm_comparison_operator" {
  description = "The arithmetic operation to use when comparing the specified statistic and threshold"
  type        = string
  default     = "LessThanThreshold"
  
  validation {
    condition = contains([
      "GreaterThanOrEqualToThreshold",
      "GreaterThanThreshold", 
      "LessThanThreshold",
      "LessThanOrEqualToThreshold"
    ], var.alarm_comparison_operator)
    error_message = "Comparison operator must be one of: GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold, LessThanOrEqualToThreshold."
  }
}

variable "treat_missing_data" {
  description = "How to treat missing data points for the alarm"
  type        = string
  default     = "notBreaching"
  
  validation {
    condition = contains(["breaching", "notBreaching", "ignore", "missing"], var.treat_missing_data)
    error_message = "treat_missing_data must be one of: breaching, notBreaching, ignore, missing."
  }
}

# ==============================================================================
# Cost Optimization Variables
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like reduced alarm frequency during non-business hours"
  type        = bool
  default     = false
}

variable "business_hours_only" {
  description = "Only send notifications during business hours (9 AM - 5 PM UTC, Monday-Friday)"
  type        = bool
  default     = false
}

# ==============================================================================
# Security Configuration Variables
# ==============================================================================

variable "enable_sns_encryption" {
  description = "Enable server-side encryption for SNS topic using AWS managed keys"
  type        = bool
  default     = true
}

variable "sns_kms_key_id" {
  description = "KMS key ID for SNS topic encryption (uses AWS managed key if not specified)"
  type        = string
  default     = "alias/aws/sns"
  
  validation {
    condition = can(regex("^(alias/[a-zA-Z0-9/_-]+|arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+|[a-f0-9-]+)$", var.sns_kms_key_id))
    error_message = "KMS key ID must be a valid key ID, ARN, or alias."
  }
}