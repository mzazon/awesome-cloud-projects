# Input variables for PartyRock AI Applications with S3 and CloudFront infrastructure
# These variables allow customization of the deployment without modifying the main configuration

# AWS Configuration Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = null
  
  validation {
    condition = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

# Environment and Naming Variables
variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "partyrock-app"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 Bucket Configuration Variables
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (random suffix will be added for uniqueness)"
  type        = string
  default     = "partyrock-app"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must start with a letter or number and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket for data protection"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either 'AES256' or 'aws:kms'."
  }
}

# Website Configuration Variables
variable "index_document" {
  description = "Index document for the static website"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Error document for the static website"
  type        = string
  default     = "error.html"
}

variable "upload_sample_website" {
  description = "Whether to upload a sample website to the S3 bucket"
  type        = bool
  default     = true
}

variable "partyrock_app_url" {
  description = "URL of the PartyRock application to embed in the website (placeholder if not provided)"
  type        = string
  default     = "YOUR_PARTYROCK_APP_URL"
}

# CloudFront Configuration Variables
variable "enable_cloudfront" {
  description = "Whether to create a CloudFront distribution for global content delivery"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class determining global distribution coverage"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition = contains([
      "PriceClass_All",
      "PriceClass_200", 
      "PriceClass_100"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "cloudfront_default_ttl" {
  description = "Default TTL (Time To Live) for CloudFront cache in seconds"
  type        = number
  default     = 86400  # 24 hours
  
  validation {
    condition     = var.cloudfront_default_ttl >= 0 && var.cloudfront_default_ttl <= 31536000
    error_message = "CloudFront default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL (Time To Live) for CloudFront cache in seconds"
  type        = number
  default     = 31536000  # 1 year
  
  validation {
    condition     = var.cloudfront_max_ttl >= 0 && var.cloudfront_max_ttl <= 31536000
    error_message = "CloudFront max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "enable_compression" {
  description = "Enable CloudFront compression for better performance"
  type        = bool
  default     = true
}

# Security Configuration Variables
variable "enable_public_access" {
  description = "Enable public read access to the S3 bucket for static website hosting"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "allowed_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "HEAD"]
  
  validation {
    condition = alltrue([
      for method in var.allowed_methods : contains([
        "GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"
      ], method)
    ])
    error_message = "Allowed methods must be valid HTTP methods."
  }
}

variable "allowed_headers" {
  description = "List of allowed headers for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

# Resource Naming Variables
variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for tag_key in keys(var.resource_tags) : can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", tag_key))
    ])
    error_message = "Tag keys must contain only alphanumeric characters and these special characters: + - = . _ : / @"
  }
}

# Random ID Configuration
variable "random_id_length" {
  description = "Length of random string to append to resource names for uniqueness"
  type        = number
  default     = 8
  
  validation {
    condition     = var.random_id_length >= 4 && var.random_id_length <= 16
    error_message = "Random ID length must be between 4 and 16 characters."
  }
}