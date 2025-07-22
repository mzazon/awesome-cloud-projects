# Variables for AWS WAF Web Application Security

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "waf_name_prefix" {
  description = "Prefix for WAF resource names"
  type        = string
  default     = "webapp-security-waf"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.waf_name_prefix))
    error_message = "WAF name prefix must contain only letters, numbers, and hyphens."
  }
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for requests per 5-minute window from a single IP"
  type        = number
  default     = 10000
  
  validation {
    condition = var.rate_limit_threshold >= 100 && var.rate_limit_threshold <= 2000000000
    error_message = "Rate limit threshold must be between 100 and 2,000,000,000."
  }
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["CN", "RU", "KP"]
  
  validation {
    condition = alltrue([
      for country in var.blocked_countries : can(regex("^[A-Z]{2}$", country))
    ])
    error_message = "Country codes must be valid ISO 3166-1 alpha-2 codes (e.g., US, CN, RU)."
  }
}

variable "blocked_ip_addresses" {
  description = "List of IP addresses or CIDR blocks to block"
  type        = list(string)
  default     = ["192.0.2.44/32", "203.0.113.0/24"]
  
  validation {
    condition = alltrue([
      for ip in var.blocked_ip_addresses : can(cidrhost(ip, 0))
    ])
    error_message = "All entries must be valid IP addresses or CIDR blocks."
  }
}

variable "enable_bot_control" {
  description = "Enable AWS Managed Bot Control rule set"
  type        = bool
  default     = true
}

variable "enable_geo_blocking" {
  description = "Enable geographic blocking rules"
  type        = bool
  default     = true
}

variable "enable_ip_blocking" {
  description = "Enable IP address blocking rules"
  type        = bool
  default     = true
}

variable "enable_rate_limiting" {
  description = "Enable rate limiting rules"
  type        = bool
  default     = true
}

variable "enable_custom_patterns" {
  description = "Enable custom regex pattern matching"
  type        = bool
  default     = true
}

variable "enable_waf_logging" {
  description = "Enable WAF logging to CloudWatch"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for blocked requests CloudWatch alarm"
  type        = number
  default     = 1000
  
  validation {
    condition = var.cloudwatch_alarm_threshold > 0
    error_message = "CloudWatch alarm threshold must be greater than 0."
  }
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

variable "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID to associate with WAF (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.cloudfront_distribution_id == "" || can(regex("^[A-Z0-9]+$", var.cloudfront_distribution_id))
    error_message = "CloudFront Distribution ID must be a valid distribution identifier or empty string."
  }
}

variable "create_dashboard" {
  description = "Create CloudWatch dashboard for WAF monitoring"
  type        = bool
  default     = true
}

variable "custom_regex_patterns" {
  description = "Custom regex patterns for threat detection"
  type        = list(string)
  default = [
    "(?i)(union.*select|select.*from|insert.*into|drop.*table)",
    "(?i)(<script|javascript:|onerror=|onload=)",
    "(?i)(\\.\\./)|(\\\\\\.\\.\\\\)",
    "(?i)(cmd\\.exe|powershell|/bin/bash|/bin/sh)"
  ]
}