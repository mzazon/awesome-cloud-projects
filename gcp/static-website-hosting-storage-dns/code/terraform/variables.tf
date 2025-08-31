# Core project configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Website configuration
variable "domain_name" {
  description = "The domain name for the static website (e.g., example.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format (e.g., example.com)."
  }
}

variable "bucket_location" {
  description = "The location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "asia-east1",
      "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "The storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# DNS configuration
variable "dns_zone_description" {
  description = "Description for the Cloud DNS managed zone"
  type        = string
  default     = "DNS zone for static website hosting"
}

variable "dns_record_ttl" {
  description = "TTL (Time To Live) for DNS records in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.dns_record_ttl >= 60 && var.dns_record_ttl <= 86400
    error_message = "DNS record TTL must be between 60 and 86400 seconds."
  }
}

# Website content configuration
variable "index_html_content" {
  description = "Custom HTML content for index.html file"
  type        = string
  default     = ""
}

variable "error_html_content" {
  description = "Custom HTML content for 404.html error page"
  type        = string
  default     = ""
}

variable "enable_public_access" {
  description = "Enable public read access to the storage bucket"
  type        = bool
  default     = true
}

# Resource naming and tagging
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "static-website"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "static-website"
    environment = "production"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Advanced configuration
variable "cache_control_max_age" {
  description = "Cache-Control max-age directive for static content (in seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.cache_control_max_age >= 300 && var.cache_control_max_age <= 31536000
    error_message = "Cache control max-age must be between 300 seconds (5 minutes) and 31536000 seconds (1 year)."
  }
}

variable "enable_cors" {
  description = "Enable CORS (Cross-Origin Resource Sharing) for the storage bucket"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "List of origins allowed for CORS requests"
  type        = list(string)
  default     = ["*"]
}

variable "cors_methods" {
  description = "List of HTTP methods allowed for CORS requests"
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
  validation {
    condition = alltrue([
      for method in var.cors_methods : contains(["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"], method)
    ])
    error_message = "CORS methods must be valid HTTP methods: GET, POST, PUT, DELETE, HEAD, OPTIONS."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning for the storage bucket"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Lifecycle management rules for the storage bucket"
  type = list(object({
    action_type          = string
    action_storage_class = optional(string)
    condition_age        = optional(number)
    condition_matches_storage_class = optional(list(string))
  }))
  default = []
}