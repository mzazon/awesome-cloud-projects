# Variables for AWS WAF Rate Limiting Configuration

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|test|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "waf-protection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "waf_scope" {
  description = "The scope of the WAF Web ACL (CLOUDFRONT or REGIONAL)"
  type        = string
  default     = "CLOUDFRONT"
  
  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.waf_scope)
    error_message = "WAF scope must be either CLOUDFRONT or REGIONAL."
  }
}

variable "rate_limit_threshold" {
  description = "Number of requests per 5-minute period before rate limiting is triggered"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.rate_limit_threshold >= 100 && var.rate_limit_threshold <= 20000000
    error_message = "Rate limit threshold must be between 100 and 20,000,000 requests per 5 minutes."
  }
}

variable "enable_sample_requests" {
  description = "Whether to enable sampling of web requests for rules"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_metrics" {
  description = "Whether to enable CloudWatch metrics for WAF rules"
  type        = bool
  default     = true
}

variable "enable_waf_logging" {
  description = "Whether to enable WAF logging to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "redacted_fields" {
  description = "List of header fields to redact in WAF logs for privacy"
  type        = list(string)
  default     = ["authorization", "cookie"]
}

variable "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID to associate with WAF (optional)"
  type        = string
  default     = ""
}

variable "application_load_balancer_arn" {
  description = "Application Load Balancer ARN to associate with WAF (optional)"
  type        = string
  default     = ""
}

variable "enable_ip_reputation_rule" {
  description = "Whether to enable AWS IP reputation list managed rule"
  type        = bool
  default     = true
}

variable "enable_known_bad_inputs_rule" {
  description = "Whether to enable AWS known bad inputs managed rule"
  type        = bool
  default     = false
}

variable "enable_core_rule_set" {
  description = "Whether to enable AWS Core Rule Set (OWASP Top 10)"
  type        = bool
  default     = false
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for WAF monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = ""
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Local values for computed configurations
locals {
  # Generate unique resource names
  resource_suffix = random_id.suffix.hex
  
  # WAF Web ACL name
  web_acl_name = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # CloudWatch log group name
  log_group_name = "/aws/wafv2/${local.web_acl_name}"
  
  # Dashboard name
  dashboard_name = var.dashboard_name != "" ? var.dashboard_name : "WAF-Security-Dashboard-${local.resource_suffix}"
  
  # Determine region based on WAF scope
  waf_region = var.waf_scope == "CLOUDFRONT" ? "us-east-1" : data.aws_region.current.name
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "web-application-firewalls-aws-waf-rate-limiting-rules"
    },
    var.additional_tags
  )
}