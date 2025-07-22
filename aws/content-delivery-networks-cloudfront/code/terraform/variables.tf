# General Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "advanced-cdn"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.project_name))
    error_message = "Project name must be lowercase, alphanumeric with hyphens, max 20 characters."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# S3 Variables
variable "s3_bucket_name" {
  description = "Name for S3 bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow S3 bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

# CloudFront Variables
variable "price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_All"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "Price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "enable_compression" {
  description = "Enable compression for CloudFront distribution"
  type        = bool
  default     = true
}

variable "default_root_object" {
  description = "Default root object for CloudFront distribution"
  type        = string
  default     = "index.html"
}

variable "custom_origin_domain" {
  description = "Custom origin domain name"
  type        = string
  default     = "httpbin.org"
}

# WAF Variables
variable "enable_waf" {
  description = "Enable AWS WAF for CloudFront distribution"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5-minute window per IP)"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000."
  }
}

variable "waf_geo_restriction_type" {
  description = "Type of geo restriction (none, whitelist, blacklist)"
  type        = string
  default     = "none"
  
  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.waf_geo_restriction_type)
    error_message = "Geo restriction type must be one of: none, whitelist, blacklist."
  }
}

variable "waf_geo_restriction_locations" {
  description = "List of country codes for geo restriction"
  type        = list(string)
  default     = []
}

# Lambda@Edge Variables
variable "enable_lambda_edge" {
  description = "Enable Lambda@Edge functions"
  type        = bool
  default     = true
}

variable "lambda_edge_timeout" {
  description = "Lambda@Edge function timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_edge_timeout >= 1 && var.lambda_edge_timeout <= 30
    error_message = "Lambda@Edge timeout must be between 1 and 30 seconds."
  }
}

variable "lambda_edge_memory_size" {
  description = "Lambda@Edge function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_edge_memory_size >= 128 && var.lambda_edge_memory_size <= 10240
    error_message = "Lambda@Edge memory size must be between 128 and 10240 MB."
  }
}

# CloudFront Functions Variables
variable "enable_cloudfront_functions" {
  description = "Enable CloudFront Functions"
  type        = bool
  default     = true
}

# Monitoring Variables
variable "enable_real_time_logs" {
  description = "Enable CloudFront real-time logs"
  type        = bool
  default     = true
}

variable "real_time_logs_kinesis_shard_count" {
  description = "Number of shards for Kinesis stream for real-time logs"
  type        = number
  default     = 1
  
  validation {
    condition     = var.real_time_logs_kinesis_shard_count >= 1
    error_message = "Kinesis shard count must be at least 1."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid value."
  }
}

# KeyValueStore Variables
variable "enable_key_value_store" {
  description = "Enable CloudFront KeyValueStore"
  type        = bool
  default     = true
}

variable "key_value_store_initial_data" {
  description = "Initial key-value pairs for CloudFront KeyValueStore"
  type        = map(string)
  default = {
    maintenance_mode = "false"
    feature_flags    = "{\"new_ui\": true, \"beta_features\": false}"
    redirect_rules   = "{\"old_domain\": \"new_domain.com\", \"legacy_path\": \"/new-path\"}"
  }
}

# SSL/TLS Variables
variable "minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version"
  type        = string
  default     = "TLSv1.2_2021"
  
  validation {
    condition = contains([
      "SSLv3", "TLSv1", "TLSv1_2016", "TLSv1.1_2016", "TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021"
    ], var.minimum_protocol_version)
    error_message = "Minimum protocol version must be a valid CloudFront SSL policy."
  }
}

# Cache Behavior Variables
variable "cache_policy_name" {
  description = "Name of the cache policy to use (Managed-CachingOptimized, Managed-CachingDisabled, etc.)"
  type        = string
  default     = "Managed-CachingOptimized"
}

variable "origin_request_policy_name" {
  description = "Name of the origin request policy to use"
  type        = string
  default     = "Managed-CORS-S3Origin"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}