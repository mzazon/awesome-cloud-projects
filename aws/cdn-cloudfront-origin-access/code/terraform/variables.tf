# Input variables for the CloudFront CDN infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "cdn-project"

  validation {
    condition = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket names (will be combined with random suffix for uniqueness)"
  type        = string
  default     = "cdn-content"

  validation {
    condition = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "enable_waf" {
  description = "Whether to enable AWS WAF protection for CloudFront distribution"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Whether to enable CloudFront access logging"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_All"

  validation {
    condition = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "Price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "minimum_protocol_version" {
  description = "Minimum TLS protocol version for CloudFront distribution"
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "TLSv1.2_2021",
      "TLSv1.2_2019",
      "TLSv1.1_2016",
      "TLSv1_2016"
    ], var.minimum_protocol_version)
    error_message = "Minimum protocol version must be a valid CloudFront TLS version."
  }
}

variable "default_cache_ttl" {
  description = "Default time to live (seconds) for cached objects"
  type        = number
  default     = 86400

  validation {
    condition = var.default_cache_ttl >= 0 && var.default_cache_ttl <= 31536000
    error_message = "Default cache TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "max_cache_ttl" {
  description = "Maximum time to live (seconds) for cached objects"
  type        = number
  default     = 31536000

  validation {
    condition = var.max_cache_ttl >= 0 && var.max_cache_ttl <= 31536000
    error_message = "Maximum cache TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF rules (requests per 5-minute window)"
  type        = number
  default     = 2000

  validation {
    condition = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000 requests per 5-minute window."
  }
}

variable "error_threshold" {
  description = "Threshold for 4xx error rate alarm (percentage)"
  type        = number
  default     = 5.0

  validation {
    condition = var.error_threshold >= 0 && var.error_threshold <= 100
    error_message = "Error threshold must be between 0 and 100 percent."
  }
}

variable "cache_hit_threshold" {
  description = "Minimum cache hit rate threshold for alarm (percentage)"
  type        = number
  default     = 80.0

  validation {
    condition = var.cache_hit_threshold >= 0 && var.cache_hit_threshold <= 100
    error_message = "Cache hit threshold must be between 0 and 100 percent."
  }
}

variable "custom_domain" {
  description = "Custom domain name for CloudFront distribution (optional)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for custom domain (required if custom_domain is set)"
  type        = string
  default     = ""
}

variable "geo_restriction_type" {
  description = "Type of geo restriction (none, whitelist, blacklist)"
  type        = string
  default     = "none"

  validation {
    condition = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "Geo restriction type must be one of: none, whitelist, blacklist."
  }
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restriction"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}