# Project and location variables
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "enterprise-knowledge"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Storage configuration
variable "storage_class" {
  description = "Storage class for the document bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the storage bucket"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                   = optional(number)
      created_before        = optional(string)
      with_state           = optional(string)
      matches_storage_class = optional(list(string))
    })
  }))
  default = [
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition = {
        age = 30
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition = {
        age = 90
      }
    }
  ]
}

# Discovery Engine configuration
variable "search_engine_config" {
  description = "Configuration for the Discovery Engine search"
  type = object({
    search_tier                      = optional(string, "SEARCH_TIER_STANDARD")
    enable_auto_language_detection   = optional(bool, true)
    enable_personalization          = optional(bool, true)
    enable_search_results_ordering   = optional(bool, true)
  })
  default = {}
}

variable "discovery_engine_location" {
  description = "Location for Discovery Engine resources (global is recommended)"
  type        = string
  default     = "global"
}

# BigQuery configuration
variable "bigquery_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "bigquery_deletion_protection" {
  description = "Enable deletion protection for BigQuery dataset"
  type        = bool
  default     = false
}

# IAM configuration
variable "knowledge_readers" {
  description = "List of users/groups with knowledge discovery reader access"
  type        = list(string)
  default     = []
}

variable "knowledge_admins" {
  description = "List of users/groups with knowledge discovery admin access"
  type        = list(string)
  default     = []
}

# Sample data configuration
variable "create_sample_documents" {
  description = "Whether to create and upload sample documents"
  type        = bool
  default     = true
}

variable "sample_documents" {
  description = "Sample documents to create for testing"
  type = map(object({
    content = string
    path    = string
  }))
  default = {
    "hr_policy" = {
      content = <<-EOT
        Employee Handbook - Remote Work Policy
        
        Effective Date: January 2024
        
        Remote Work Guidelines:
        - Employees may work remotely up to 3 days per week
        - Home office setup must meet security requirements
        - Daily check-ins required with immediate supervisor
        - Collaboration tools: Google Meet, Slack, Asana
        
        Equipment Policy:
        - Company provides laptop, monitor, and chair
        - IT support available 24/7 for remote workers
        - VPN access mandatory for all remote connections
      EOT
      path = "documents/hr_policy.txt"
    }
    "api_documentation" = {
      content = <<-EOT
        API Documentation - Customer Service Platform
        
        Version: 2.1.0
        Last Updated: March 2024
        
        Authentication:
        - OAuth 2.0 with JWT tokens
        - API key required for all requests
        - Rate limiting: 1000 requests per hour
        
        Endpoints:
        - GET /customers - Retrieve customer list
        - POST /customers - Create new customer
        - PUT /customers/{id} - Update customer information
        - DELETE /customers/{id} - Remove customer
        
        Error Handling:
        - 400: Bad Request - Invalid parameters
        - 401: Unauthorized - Invalid credentials
        - 429: Too Many Requests - Rate limit exceeded
      EOT
      path = "documents/api_documentation.txt"
    }
    "financial_report" = {
      content = <<-EOT
        Quarterly Financial Report - Q1 2024
        
        Revenue Summary:
        - Total Revenue: $2.5M (up 15% YoY)
        - Subscription Revenue: $1.8M (72% of total)
        - Professional Services: $700K (28% of total)
        
        Expenses:
        - Personnel: $1.2M (48% of revenue)
        - Technology: $400K (16% of revenue)
        - Marketing: $300K (12% of revenue)
        - Operations: $200K (8% of revenue)
        
        Key Metrics:
        - Monthly Recurring Revenue (MRR): $600K
        - Customer Acquisition Cost (CAC): $150
        - Customer Lifetime Value (CLV): $2,400
      EOT
      path = "documents/financial_report.txt"
    }
  }
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard creation"
  type        = bool
  default     = true
}

# Tags and labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "enterprise-knowledge-discovery"
    managed-by  = "terraform"
  }
}