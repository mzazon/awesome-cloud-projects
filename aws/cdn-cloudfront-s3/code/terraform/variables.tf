# Variables for CloudFront and S3 CDN infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cdn-content"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "cloudfront_default_ttl" {
  description = "Default TTL (in seconds) for CloudFront cache behavior"
  type        = number
  default     = 86400 # 24 hours
  
  validation {
    condition = var.cloudfront_default_ttl >= 0 && var.cloudfront_default_ttl <= 31536000
    error_message = "Default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL (in seconds) for CloudFront cache behavior"
  type        = number
  default     = 31536000 # 1 year
  
  validation {
    condition = var.cloudfront_max_ttl >= 0 && var.cloudfront_max_ttl <= 31536000
    error_message = "Maximum TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cloudfront_min_ttl" {
  description = "Minimum TTL (in seconds) for CloudFront cache behavior"
  type        = number
  default     = 0
  
  validation {
    condition = var.cloudfront_min_ttl >= 0
    error_message = "Minimum TTL must be greater than or equal to 0."
  }
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "CloudWatch alarm threshold for 4xx error rate percentage"
  type        = number
  default     = 5.0
  
  validation {
    condition = var.error_rate_threshold > 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}

variable "origin_latency_threshold" {
  description = "CloudWatch alarm threshold for origin latency in milliseconds"
  type        = number
  default     = 1000
  
  validation {
    condition = var.origin_latency_threshold > 0
    error_message = "Origin latency threshold must be greater than 0 milliseconds."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "enable_compression" {
  description = "Enable automatic compression for CloudFront"
  type        = bool
  default     = true
}

variable "custom_error_response_code" {
  description = "Custom error response code for 404 errors"
  type        = number
  default     = 200
  
  validation {
    condition = contains([200, 404], var.custom_error_response_code)
    error_message = "Custom error response code must be 200 or 404."
  }
}

variable "custom_error_response_path" {
  description = "Custom error response path for 404 errors"
  type        = string
  default     = "/index.html"
  
  validation {
    condition = can(regex("^/.*", var.custom_error_response_path))
    error_message = "Custom error response path must start with '/'."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}