# Input Variables for Static Website Hosting Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
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
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "static-website"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "domain_name" {
  description = "Custom domain name for the website (optional). Leave empty to use CloudFront domain only."
  type        = string
  default     = ""

  validation {
    condition = var.domain_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format (e.g., example.com)."
  }
}

variable "create_route53_record" {
  description = "Whether to create Route 53 DNS record for custom domain (requires domain_name and existing hosted zone)"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "default_root_object" {
  description = "Default root object for the CloudFront distribution"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for 404 responses"
  type        = string
  default     = "error.html"
}

variable "cache_behavior_ttl" {
  description = "TTL settings for CloudFront cache behavior"
  type = object({
    default_ttl = number
    max_ttl     = number
    min_ttl     = number
  })
  default = {
    default_ttl = 86400  # 1 day
    max_ttl     = 31536000  # 1 year
    min_ttl     = 0
  }

  validation {
    condition = var.cache_behavior_ttl.min_ttl <= var.cache_behavior_ttl.default_ttl && var.cache_behavior_ttl.default_ttl <= var.cache_behavior_ttl.max_ttl
    error_message = "TTL values must satisfy: min_ttl <= default_ttl <= max_ttl."
  }
}

variable "enable_ipv6" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "enable_compression" {
  description = "Enable gzip compression for CloudFront"
  type        = bool
  default     = true
}

variable "viewer_protocol_policy" {
  description = "Protocol policy for viewers (redirect-to-https, allow-all, https-only)"
  type        = string
  default     = "redirect-to-https"

  validation {
    condition = contains(["allow-all", "redirect-to-https", "https-only"], var.viewer_protocol_policy)
    error_message = "Viewer protocol policy must be one of: allow-all, redirect-to-https, https-only."
  }
}

variable "minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "SSLv3", "TLSv1", "TLSv1_2016", "TLSv1.1_2016", "TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021"
    ], var.minimum_protocol_version)
    error_message = "Invalid minimum protocol version specified."
  }
}

variable "cors_configuration" {
  description = "CORS configuration for S3 bucket"
  type = object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  })
  default = {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}