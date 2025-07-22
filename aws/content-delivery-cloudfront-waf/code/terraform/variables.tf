# Input variables for secure content delivery infrastructure

variable "aws_region" {
  description = "AWS region for resources deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "secure-content"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "secure-content"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_waf_logging" {
  description = "Enable WAF logging to CloudWatch"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF rate-based rule (requests per 5-minute window)"
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000 requests per 5-minute window."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition = contains([
      "PriceClass_All",
      "PriceClass_200",
      "PriceClass_100"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["RU", "CN"]

  validation {
    condition = alltrue([
      for country in var.blocked_countries : can(regex("^[A-Z]{2}$", country))
    ])
    error_message = "Country codes must be valid ISO 3166-1 alpha-2 codes (e.g., US, CA, GB)."
  }
}

variable "enable_geo_restrictions" {
  description = "Enable geographic restrictions on CloudFront distribution"
  type        = bool
  default     = true
}

variable "create_sample_content" {
  description = "Create sample HTML content in S3 bucket for testing"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

variable "waf_managed_rules" {
  description = "List of AWS managed rule groups to enable in WAF"
  type = list(object({
    name     = string
    priority = number
    action   = string # "allow", "block", "count"
  }))
  default = [
    {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 1
      action   = "block"
    },
    {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 2
      action   = "block"
    },
    {
      name     = "AWSManagedRulesLinuxRuleSet"
      priority = 3
      action   = "block"
    },
    {
      name     = "AWSManagedRulesSQLiRuleSet"
      priority = 4
      action   = "block"
    }
  ]

  validation {
    condition = alltrue([
      for rule in var.waf_managed_rules : contains(["allow", "block", "count"], rule.action)
    ])
    error_message = "WAF rule actions must be one of: allow, block, count."
  }
}

variable "cache_behaviors" {
  description = "Additional cache behaviors for CloudFront distribution"
  type = list(object({
    path_pattern     = string
    target_origin_id = string
    viewer_protocol_policy = string
    cache_policy_id  = string
    compress         = bool
  }))
  default = []
}

variable "custom_error_responses" {
  description = "Custom error responses for CloudFront distribution"
  type = list(object({
    error_code         = number
    response_code      = number
    response_page_path = string
    error_caching_min_ttl = number
  }))
  default = [
    {
      error_code            = 404
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 300
    },
    {
      error_code            = 403
      response_code         = 403
      response_page_path    = "/403.html"
      error_caching_min_ttl = 300
    }
  ]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}