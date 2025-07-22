# Input Variables for Static Website with SSL Certificate
# These variables allow customization of the infrastructure deployment

variable "aws_region" {
  description = "AWS region for S3 bucket and other resources (ACM certificate will always be in us-east-1 for CloudFront)"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "domain_name" {
  description = "Primary domain name for the website (e.g., example.com)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format."
  }
}

variable "subdomain_name" {
  description = "Subdomain for the website (e.g., www). Will be combined with domain_name to create www.example.com"
  type        = string
  default     = "www"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.subdomain_name))
    error_message = "Subdomain must contain only alphanumeric characters and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name. Random suffix will be added to ensure uniqueness."
  type        = string
  default     = "static-website"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the domain. If not provided, will attempt to lookup automatically."
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket for better file management"
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront distribution price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "Price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "default_root_object" {
  description = "Default root object for the CloudFront distribution"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for 404 errors"
  type        = string
  default     = "error.html"
}

variable "minimum_protocol_version" {
  description = "Minimum TLS protocol version for HTTPS connections"
  type        = string
  default     = "TLSv1.2_2021"
  
  validation {
    condition = contains([
      "TLSv1", "TLSv1.1_2016", "TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021"
    ], var.minimum_protocol_version)
    error_message = "Minimum protocol version must be a valid CloudFront TLS version."
  }
}

variable "certificate_validation_method" {
  description = "Method to use for certificate validation (DNS or EMAIL)"
  type        = string
  default     = "DNS"
  
  validation {
    condition     = contains(["DNS", "EMAIL"], var.certificate_validation_method)
    error_message = "Certificate validation method must be either DNS or EMAIL."
  }
}

variable "cloudfront_cache_ttl" {
  description = "Default TTL (Time To Live) for CloudFront cache in seconds"
  type        = number
  default     = 86400 # 24 hours
  
  validation {
    condition     = var.cloudfront_cache_ttl >= 0 && var.cloudfront_cache_ttl <= 31536000
    error_message = "CloudFront cache TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "enable_compression" {
  description = "Enable gzip compression on CloudFront distribution"
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 support for CloudFront distribution"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "StaticWebsite"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}