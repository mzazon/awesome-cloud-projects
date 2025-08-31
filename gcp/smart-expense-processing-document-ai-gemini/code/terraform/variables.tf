# Variables for Smart Expense Processing Infrastructure
# Terraform configuration variables for GCP resources

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
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports all required services."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and identification"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "testing", "demo"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing, demo."
  }
}

# Document AI Configuration
variable "create_document_ai_processor" {
  description = "Whether to create a new Document AI processor (currently requires manual creation)"
  type        = bool
  default     = false
}

variable "document_ai_processor_id" {
  description = "The ID of an existing Document AI expense processor (required if create_document_ai_processor is false)"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.document_ai_processor_id) >= 0
    error_message = "Document AI processor ID must be provided if not creating a new processor."
  }
}

# Database Configuration
variable "database_version" {
  description = "PostgreSQL version for Cloud SQL instance"
  type        = string
  default     = "POSTGRES_15"
  
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16"
    ], var.database_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "database_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2", 
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16",
      "db-n1-highmem-2", "db-n1-highmem-4", "db-n1-highmem-8"
    ], var.database_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "database_disk_size" {
  description = "Initial disk size for the Cloud SQL instance in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.database_disk_size >= 10 && var.database_disk_size <= 30720
    error_message = "Database disk size must be between 10 and 30720 GB."
  }
}

variable "database_user" {
  description = "Username for the database application user"
  type        = string
  default     = "expense_app"
  
  validation {
    condition     = length(var.database_user) > 0
    error_message = "Database user must not be empty."
  }
}

variable "database_password" {
  description = "Password for the database application user"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.database_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for the Cloud SQL instance"
  type        = bool
  default     = true
}

# Cloud Functions Configuration
variable "max_function_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_function_instances > 0 && var.max_function_instances <= 1000
    error_message = "Max function instances must be between 1 and 1000."
  }
}

# Storage Configuration
variable "force_destroy" {
  description = "Allow destruction of non-empty storage buckets (use with caution)"
  type        = bool
  default     = false
}

# Reporting Configuration
variable "enable_scheduled_reports" {
  description = "Enable automated scheduled expense reports"
  type        = bool
  default     = true
}

variable "report_schedule" {
  description = "Cron schedule for automated reports (Cloud Scheduler format)"
  type        = string
  default     = "0 9 * * 1"  # Every Monday at 9 AM
  
  validation {
    condition     = length(var.report_schedule) > 0
    error_message = "Report schedule must be a valid cron expression."
  }
}

# AI/ML Configuration
variable "gemini_model" {
  description = "Gemini model version to use for expense validation"
  type        = string
  default     = "gemini-2.0-flash-exp"
  
  validation {
    condition = contains([
      "gemini-2.0-flash-exp", "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported version."
  }
}

variable "max_expense_amount" {
  description = "Maximum expense amount for automatic approval (in USD)"
  type        = number
  default     = 1000.00
  
  validation {
    condition     = var.max_expense_amount > 0
    error_message = "Maximum expense amount must be greater than 0."
  }
}

# Policy Configuration
variable "meal_daily_limit" {
  description = "Daily limit for meal expenses (in USD)"
  type        = number
  default     = 75.00
  
  validation {
    condition     = var.meal_daily_limit > 0
    error_message = "Meal daily limit must be greater than 0."
  }
}

variable "hotel_nightly_limit" {
  description = "Nightly limit for hotel expenses (in USD)"
  type        = number
  default     = 300.00
  
  validation {
    condition     = var.hotel_nightly_limit > 0
    error_message = "Hotel nightly limit must be greater than 0."
  }
}

variable "equipment_approval_threshold" {
  description = "Equipment expense threshold requiring manager approval (in USD)"
  type        = number
  default     = 500.00
  
  validation {
    condition     = var.equipment_approval_threshold > 0
    error_message = "Equipment approval threshold must be greater than 0."
  }
}

variable "entertainment_limit" {
  description = "Maximum limit for entertainment expenses (in USD)"
  type        = number
  default     = 150.00
  
  validation {
    condition     = var.entertainment_limit > 0
    error_message = "Entertainment limit must be greater than 0."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for expense processing notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and alerting for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# Cost Management
variable "budget_amount" {
  description = "Monthly budget amount for expense processing infrastructure (in USD)"
  type        = number
  default     = 100.00
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages (e.g., [50, 80, 100])"
  type        = list(number)
  default     = [50, 80, 100]
  
  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : 
      threshold > 0 && threshold <= 100
    ])
    error_message = "Budget alert thresholds must be between 1 and 100 percent."
  }
}

# Security Configuration
variable "enable_audit_logs" {
  description = "Enable audit logging for all supported services"
  type        = bool
  default     = true
}

variable "require_ssl" {
  description = "Require SSL/TLS for all database connections"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the database (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Note: Restrict this in production
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges :
      can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Development Configuration
variable "enable_debug_logging" {
  description = "Enable debug logging for troubleshooting (not recommended for production)"
  type        = bool
  default     = false
}