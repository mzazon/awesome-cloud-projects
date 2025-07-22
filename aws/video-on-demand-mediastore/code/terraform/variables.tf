# Input variables for the VOD platform infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
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

variable "mediastore_container_name" {
  description = "Name for the MediaStore container"
  type        = string
  default     = ""
  
  validation {
    condition = var.mediastore_container_name == "" || can(regex("^[a-zA-Z0-9_-]+$", var.mediastore_container_name))
    error_message = "MediaStore container name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_All"
  
  validation {
    condition = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "cloudfront_comment" {
  description = "Comment for the CloudFront distribution"
  type        = string
  default     = "VOD Platform Distribution"
}

variable "enable_cloudfront_logging" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = false
}

variable "cloudfront_log_bucket" {
  description = "S3 bucket for CloudFront access logs (required if logging enabled)"
  type        = string
  default     = ""
}

variable "mediastore_cors_max_age" {
  description = "Maximum age in seconds for CORS preflight requests"
  type        = number
  default     = 3000
  
  validation {
    condition = var.mediastore_cors_max_age >= 0 && var.mediastore_cors_max_age <= 86400
    error_message = "CORS max age must be between 0 and 86400 seconds."
  }
}

variable "cloudfront_default_ttl" {
  description = "Default TTL for CloudFront caching (in seconds)"
  type        = number
  default     = 86400
  
  validation {
    condition = var.cloudfront_default_ttl >= 0
    error_message = "Default TTL must be a non-negative number."
  }
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL for CloudFront caching (in seconds)"
  type        = number
  default     = 31536000
  
  validation {
    condition = var.cloudfront_max_ttl >= 0
    error_message = "Maximum TTL must be a non-negative number."
  }
}

variable "enable_mediastore_metrics" {
  description = "Enable CloudWatch metrics for MediaStore container"
  type        = bool
  default     = true
}

variable "lifecycle_transition_days" {
  description = "Number of days before transitioning to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.lifecycle_transition_days >= 1
    error_message = "Transition days must be at least 1."
  }
}

variable "lifecycle_expiration_days" {
  description = "Number of days before object expiration"
  type        = number
  default     = 90
  
  validation {
    condition = var.lifecycle_expiration_days >= 1
    error_message = "Expiration days must be at least 1."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}