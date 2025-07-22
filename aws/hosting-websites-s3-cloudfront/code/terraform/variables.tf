# Variables for static website hosting infrastructure

variable "domain_name" {
  description = "The root domain name for the website (e.g., example.com)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain (e.g., example.com)."
  }
}

variable "aws_region" {
  description = "AWS region for S3 bucket and other resources"
  type        = string
  default     = "us-east-1"
}

variable "subdomain" {
  description = "Subdomain prefix for the website (will be prepended to domain_name)"
  type        = string
  default     = "www"
}

variable "create_route53_zone" {
  description = "Whether to create a new Route 53 hosted zone for the domain"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route 53 hosted zone ID (required if create_route53_zone is false)"
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for geographic distribution"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "index_document" {
  description = "Index document for the website"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for the website"
  type        = string
  default     = "error.html"
}

variable "enable_compression" {
  description = "Enable CloudFront compression"
  type        = bool
  default     = true
}

variable "minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"
}

variable "default_ttl" {
  description = "Default TTL for CloudFront cache behavior (in seconds)"
  type        = number
  default     = 86400
}

variable "max_ttl" {
  description = "Maximum TTL for CloudFront cache behavior (in seconds)"
  type        = number
  default     = 31536000
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "static-website"
    ManagedBy   = "terraform"
  }
}