# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "customer-service"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# Cloud Storage Configuration
variable "storage_class" {
  description = "Storage class for the knowledge base bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket (multi-region, dual-region, or region)"
  type        = string
  default     = "US"
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects transition to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# Vertex AI Search Configuration
variable "search_tier" {
  description = "Search tier for Vertex AI Search (SEARCH_TIER_STANDARD or SEARCH_TIER_ENTERPRISE)"
  type        = string
  default     = "SEARCH_TIER_STANDARD"
  validation {
    condition = contains([
      "SEARCH_TIER_STANDARD", "SEARCH_TIER_ENTERPRISE"
    ], var.search_tier)
    error_message = "Search tier must be SEARCH_TIER_STANDARD or SEARCH_TIER_ENTERPRISE."
  }
}

variable "industry_vertical" {
  description = "Industry vertical for the search engine"
  type        = string
  default     = "GENERIC"
  validation {
    condition = contains([
      "GENERIC", "MEDIA", "HEALTHCARE_FHIR"
    ], var.industry_vertical)
    error_message = "Industry vertical must be one of: GENERIC, MEDIA, HEALTHCARE_FHIR."
  }
}

# Cloud Run Configuration
variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "CPU must be a valid Cloud Run CPU value."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "1Gi"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.cloud_run_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Contact Center AI Configuration
variable "enable_contact_center_ai" {
  description = "Whether to enable Contact Center AI features"
  type        = bool
  default     = true
}

variable "analysis_percentage" {
  description = "Percentage of conversations to analyze with Contact Center AI"
  type        = number
  default     = 100
  validation {
    condition     = var.analysis_percentage >= 0 && var.analysis_percentage <= 100
    error_message = "Analysis percentage must be between 0 and 100."
  }
}

# Knowledge Base Configuration
variable "upload_sample_documents" {
  description = "Whether to upload sample knowledge base documents"
  type        = bool
  default     = true
}

variable "knowledge_base_documents" {
  description = "List of knowledge base documents to create"
  type = list(object({
    name    = string
    content = string
  }))
  default = [
    {
      name = "customer-faq.txt"
      content = <<-EOF
        Frequently Asked Questions
        
        Q: How do I reset my password?
        A: To reset your password, click on the "Forgot Password" link on the login page and follow the instructions sent to your email.
        
        Q: What are your business hours?
        A: Our customer service is available Monday through Friday, 9 AM to 6 PM EST.
        
        Q: How do I cancel my subscription?
        A: You can cancel your subscription by logging into your account and navigating to the billing section.
        
        Q: What payment methods do you accept?
        A: We accept all major credit cards, PayPal, and bank transfers.
      EOF
    },
    {
      name = "troubleshooting-guide.txt"
      content = <<-EOF
        Technical Troubleshooting Guide
        
        Issue: Login Problems
        Solution: Clear browser cache and cookies, ensure JavaScript is enabled, try incognito mode.
        
        Issue: Payment Processing Errors
        Solution: Verify card details, check with bank for international transaction blocks, try alternative payment method.
        
        Issue: Account Access Issues
        Solution: Confirm email address, check spam folder for verification emails, contact support if account is locked.
        
        Issue: Performance Issues
        Solution: Check internet connection, try different browser, clear application cache.
      EOF
    },
    {
      name = "policies.txt"
      content = <<-EOF
        Company Policies and Procedures
        
        Refund Policy: Full refunds available within 30 days of purchase with proof of purchase.
        
        Privacy Policy: We protect customer data according to GDPR and CCPA regulations.
        
        Return Policy: Items must be returned in original condition within 14 days.
        
        Shipping Policy: Standard shipping takes 3-5 business days, expedited shipping available.
      EOF
    }
  ]
}

# Security Configuration
variable "enable_audit_logs" {
  description = "Whether to enable audit logging for all services"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access the Cloud Run service"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Allow all by default, restrict in production
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "customer-service-automation"
    managed-by  = "terraform"
  }
}

# API Configuration
variable "enable_required_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "contactcenteraiplatform.googleapis.com",
    "discoveryengine.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}