# ============================================================================
# Smart Email Template Generation with Gemini and Firestore - Variables
# ============================================================================
# This file defines all the input variables for the Terraform configuration
# that deploys an AI-powered email template generator using Google Cloud
# services including Vertex AI Gemini, Firestore, and Cloud Functions.
# ============================================================================

# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "testing", "demo"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing, demo."
  }
}

# ============================================================================
# FIRESTORE CONFIGURATION
# ============================================================================

variable "database_name" {
  description = "Name prefix for the Firestore database (will be suffixed with random string)"
  type        = string
  default     = "email-templates"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.database_name))
    error_message = "Database name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "firestore_location" {
  description = "Location for the Firestore database (must be a multi-region or region)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west1", "europe-west1", "asia-east1",
      "nam5", "eur3", "asia-northeast1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Firestore database to prevent accidental data loss"
  type        = bool
  default     = true
}

# ============================================================================
# CLOUD FUNCTION CONFIGURATION
# ============================================================================

variable "function_name" {
  description = "Name prefix for the Cloud Function (will be suffixed with random string)"
  type        = string
  default     = "email-template-generator"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.function_name))
    error_message = "Function name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances (0 for cold starts)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= var.function_max_instances
    error_message = "Function min instances must be between 0 and max instances value."
  }
}

variable "allow_unauthenticated_invocations" {
  description = "Allow unauthenticated invocations of the Cloud Function (not recommended for production)"
  type        = bool
  default     = true
}

# ============================================================================
# VERTEX AI CONFIGURATION
# ============================================================================

variable "vertex_ai_location" {
  description = "Location for Vertex AI services (must support Gemini models)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east4", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support Gemini models."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for email template generation"
  type        = string
  default     = "gemini-1.5-flash"
  
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be one of the supported versions."
  }
}

# ============================================================================
# DATA INITIALIZATION
# ============================================================================

variable "initialize_sample_data" {
  description = "Create and deploy a function to initialize sample data in Firestore"
  type        = bool
  default     = true
}

variable "sample_company_name" {
  description = "Company name for sample data initialization"
  type        = string
  default     = "TechStart Solutions"
}

variable "sample_industry" {
  description = "Industry for sample data initialization"
  type        = string
  default     = "Software"
}

variable "sample_brand_voice" {
  description = "Brand voice for sample data initialization"
  type        = string
  default     = "innovative, trustworthy, solution-focused"
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring alerts for the email template generator"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring alerts (leave empty to disable email notifications)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "error_threshold" {
  description = "Error rate threshold for triggering alerts (between 0.0 and 1.0)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.error_threshold >= 0.0 && var.error_threshold <= 1.0
    error_message = "Error threshold must be between 0.0 and 1.0."
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE
# ============================================================================

variable "enable_resource_tagging" {
  description = "Enable Google Cloud resource tagging for compliance and organization"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logging for Firestore and Cloud Function access"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the Cloud Function (use ['*'] for all origins)"
  type        = list(string)
  default     = ["*"]
}

# ============================================================================
# COST OPTIMIZATION
# ============================================================================

variable "enable_lifecycle_policies" {
  description = "Enable lifecycle policies for Cloud Storage buckets to manage costs"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# ============================================================================
# ADVANCED CONFIGURATION
# ============================================================================

variable "custom_domain" {
  description = "Custom domain for the Cloud Function (optional, requires domain verification)"
  type        = string
  default     = ""
}

variable "vpc_connector" {
  description = "VPC connector for Cloud Function network access (optional)"
  type        = string
  default     = ""
}

variable "service_account_email" {
  description = "Custom service account email for Cloud Function (optional, will create one if not provided)"
  type        = string
  default     = ""
}

variable "kms_key_name" {
  description = "KMS key for encrypting function environment variables (optional)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# ============================================================================
# FEATURE FLAGS
# ============================================================================

variable "enable_experimental_features" {
  description = "Enable experimental features (use with caution in production)"
  type        = bool
  default     = false
}

variable "enable_debug_logging" {
  description = "Enable debug logging for troubleshooting (may expose sensitive information)"
  type        = bool
  default     = false
}

variable "enable_performance_monitoring" {
  description = "Enable detailed performance monitoring and tracing"
  type        = bool
  default     = true
}