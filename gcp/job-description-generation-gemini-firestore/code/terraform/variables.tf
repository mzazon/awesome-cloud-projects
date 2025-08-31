# =============================================================================
# Variables for Job Description Generation with Gemini and Firestore
# =============================================================================
# This file defines all configurable variables for the HR automation
# infrastructure deployment.
# =============================================================================

# =============================================================================
# Project Configuration Variables
# =============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created. If create_project is true, this will be ignored in favor of project_id_prefix."
  type        = string
  default     = null
  
  validation {
    condition     = var.project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_id_prefix" {
  description = "Prefix for the project ID when creating a new project. Will be suffixed with timestamp."
  type        = string
  default     = "hr-automation"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,20}$", var.project_id_prefix))
    error_message = "Project ID prefix must be 5-21 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "create_project" {
  description = "Whether to create a new Google Cloud project for this deployment."
  type        = bool
  default     = false
}

variable "billing_account" {
  description = "The billing account ID to associate with the project (required if create_project is true)."
  type        = string
  default     = null
  
  validation {
    condition     = var.billing_account == null || can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "Billing account must be in the format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "org_id" {
  description = "The organization ID where the project will be created (optional, used only if create_project is true)."
  type        = string
  default     = null
}

variable "folder_id" {
  description = "The folder ID where the project will be created (optional, used only if create_project is true and org_id is not specified)."
  type        = string
  default     = null
}

# =============================================================================
# Regional Configuration
# =============================================================================

variable "region" {
  description = "The Google Cloud region where resources will be deployed."
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (optional)."
  type        = string
  default     = null
}

# =============================================================================
# Environment and Naming
# =============================================================================

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# =============================================================================
# Firestore Configuration
# =============================================================================

variable "firestore_database_name" {
  description = "The name of the Firestore database to create."
  type        = string
  default     = "(default)"
  
  validation {
    condition = var.firestore_database_name == "(default)" || can(regex("^[a-z][a-z0-9-]{2,62}[a-z0-9]$", var.firestore_database_name))
    error_message = "Database name must be 4-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens, or be '(default)'."
  }
}

variable "enable_firestore_pitr" {
  description = "Whether to enable Point-in-Time Recovery for Firestore."
  type        = bool
  default     = false
}

variable "firestore_delete_protection" {
  description = "Whether to enable delete protection for the Firestore database."
  type        = bool
  default     = true
}

# =============================================================================
# Company Information Variables
# =============================================================================

variable "company_name" {
  description = "The name of the company for job descriptions."
  type        = string
  default     = "TechInnovate Solutions"
  
  validation {
    condition     = length(var.company_name) > 0 && length(var.company_name) <= 100
    error_message = "Company name must be between 1 and 100 characters."
  }
}

variable "company_mission" {
  description = "The company mission statement."
  type        = string
  default     = "Empowering businesses through innovative technology solutions"
  
  validation {
    condition     = length(var.company_mission) > 0 && length(var.company_mission) <= 500
    error_message = "Company mission must be between 1 and 500 characters."
  }
}

variable "company_values" {
  description = "List of company values."
  type        = list(string)
  default     = ["Innovation", "Collaboration", "Integrity", "Excellence"]
  
  validation {
    condition     = length(var.company_values) > 0 && length(var.company_values) <= 10
    error_message = "Company values must contain between 1 and 10 items."
  }
}

variable "company_culture_description" {
  description = "Description of the company culture."
  type        = string
  default     = "Fast-paced, collaborative environment with focus on continuous learning and growth"
  
  validation {
    condition     = length(var.company_culture_description) > 0 && length(var.company_culture_description) <= 1000
    error_message = "Company culture description must be between 1 and 1000 characters."
  }
}

variable "company_benefits" {
  description = "List of company benefits and perks."
  type        = list(string)
  default = [
    "Competitive salary",
    "Health insurance",
    "Remote work options",
    "Professional development budget",
    "Flexible hours",
    "401(k) matching"
  ]
  
  validation {
    condition     = length(var.company_benefits) > 0 && length(var.company_benefits) <= 20
    error_message = "Company benefits must contain between 1 and 20 items."
  }
}

variable "work_environment" {
  description = "Description of the work environment (e.g., remote, hybrid, on-site)."
  type        = string
  default     = "Hybrid office model with flexible hours"
  
  validation {
    condition     = length(var.work_environment) > 0 && length(var.work_environment) <= 200
    error_message = "Work environment description must be between 1 and 200 characters."
  }
}

# =============================================================================
# Cloud Functions Configuration
# =============================================================================

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (e.g., 256Mi, 512Mi, 1Gi)."
  type        = string
  default     = "512Mi"
  
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.function_memory))
    error_message = "Function memory must be in the format of number followed by Mi or Gi (e.g., 256Mi, 1Gi)."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds."
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances."
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for cold start)."
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= var.function_max_instances
    error_message = "Function min instances must be between 0 and the max instances value."
  }
}

# =============================================================================
# Vertex AI Configuration
# =============================================================================

variable "gemini_model" {
  description = "The Vertex AI Gemini model to use for text generation."
  type        = string
  default     = "gemini-1.5-flash"
  
  validation {
    condition = contains([
      "gemini-1.5-flash",
      "gemini-1.5-pro",
      "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be one of: gemini-1.5-flash, gemini-1.5-pro, gemini-1.0-pro."
  }
}

# =============================================================================
# Security and Access Configuration
# =============================================================================

variable "allow_unauthenticated_access" {
  description = "Whether to allow unauthenticated access to Cloud Functions. Set to false for production."
  type        = bool
  default     = true
}

# =============================================================================
# Monitoring and Observability
# =============================================================================

variable "enable_monitoring" {
  description = "Whether to enable monitoring and logging metrics."
  type        = bool
  default     = true
}

variable "enable_detailed_logging" {
  description = "Whether to enable detailed logging for functions."
  type        = bool
  default     = false
}

# =============================================================================
# Cost Management
# =============================================================================

variable "enable_cost_alerts" {
  description = "Whether to enable cost monitoring and alerts."
  type        = bool
  default     = false
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts (only used if enable_cost_alerts is true)."
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

# =============================================================================
# Advanced Configuration
# =============================================================================

variable "custom_domain" {
  description = "Custom domain for the Cloud Functions (optional)."
  type        = string
  default     = null
  
  validation {
    condition     = var.custom_domain == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\\.[a-zA-Z]{2,}$", var.custom_domain))
    error_message = "Custom domain must be a valid domain name."
  }
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the API."
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "rate_limit_per_minute" {
  description = "Rate limit per minute for API calls (0 to disable)."
  type        = number
  default     = 60
  
  validation {
    condition     = var.rate_limit_per_minute >= 0
    error_message = "Rate limit must be 0 or greater."
  }
}

variable "enable_api_key_auth" {
  description = "Whether to require API key authentication for function access."
  type        = bool
  default     = false
}

# =============================================================================
# Backup and Recovery
# =============================================================================

variable "enable_backup_schedule" {
  description = "Whether to enable automated Firestore backup schedule."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups (only used if enable_backup_schedule is true)."
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# =============================================================================
# Testing and Development
# =============================================================================

variable "enable_test_data" {
  description = "Whether to create additional test data in Firestore for development and testing."
  type        = bool
  default     = true
}

variable "test_job_templates" {
  description = "Additional job templates to create for testing purposes."
  type = list(object({
    id           = string
    title        = string
    department   = string
    level        = string
    description  = string
  }))
  default = []
}

# =============================================================================
# External Integrations
# =============================================================================

variable "webhook_endpoints" {
  description = "List of webhook endpoints to notify when job descriptions are generated."
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for url in var.webhook_endpoints : can(regex("^https?://", url))
    ])
    error_message = "All webhook endpoints must be valid HTTP or HTTPS URLs."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)."
  type        = string
  default     = null
  sensitive   = true
  
  validation {
    condition     = var.slack_webhook_url == null || can(regex("^https://hooks\\.slack\\.com/", var.slack_webhook_url))
    error_message = "Slack webhook URL must be a valid Slack webhook URL."
  }
}

# =============================================================================
# Performance Tuning
# =============================================================================

variable "function_cpu" {
  description = "CPU allocation for Cloud Functions (number of CPUs)."
  type        = number
  default     = null
  
  validation {
    condition     = var.function_cpu == null || (var.function_cpu >= 0.083 && var.function_cpu <= 8)
    error_message = "Function CPU must be between 0.083 and 8 CPUs, or null for automatic allocation."
  }
}

variable "enable_function_concurrency_limit" {
  description = "Whether to enable per-instance concurrency limits for functions."
  type        = bool
  default     = true
}

variable "firestore_read_cache_ttl" {
  description = "TTL for Firestore read cache in seconds (0 to disable caching)."
  type        = number
  default     = 300
  
  validation {
    condition     = var.firestore_read_cache_ttl >= 0
    error_message = "Firestore read cache TTL must be 0 or greater."
  }
}