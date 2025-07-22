# Variables for GCP compliance reporting infrastructure
variable "project_id" {
  description = "The GCP project ID for deploying compliance reporting infrastructure"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6 and 30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a, europe-west1-b)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "compliance"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-16 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "compliance_frameworks" {
  description = "List of compliance frameworks to support (SOC2, ISO27001, HIPAA, PCI)"
  type        = list(string)
  default     = ["SOC2", "ISO27001"]
  
  validation {
    condition = alltrue([
      for framework in var.compliance_frameworks : 
      contains(["SOC2", "ISO27001", "HIPAA", "PCI", "GDPR"], framework)
    ])
    error_message = "Compliance frameworks must be from: SOC2, ISO27001, HIPAA, PCI, GDPR."
  }
}

variable "audit_log_retention_days" {
  description = "Number of days to retain audit logs for compliance requirements"
  type        = number
  default     = 2555  # 7 years as required by most compliance frameworks
  
  validation {
    condition     = var.audit_log_retention_days >= 365 && var.audit_log_retention_days <= 3650
    error_message = "Audit log retention must be between 365 and 3650 days (1-10 years)."
  }
}

variable "enable_data_access_logs" {
  description = "Enable data access audit logs for enhanced compliance tracking"
  type        = bool
  default     = true
}

variable "enable_admin_activity_logs" {
  description = "Enable admin activity audit logs (always recommended for compliance)"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for compliance alerts and notifications"
  type        = string
  default     = "compliance@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "report_schedule" {
  description = "Cron schedule for automated compliance report generation"
  type        = string
  default     = "0 9 * * MON"  # Every Monday at 9:00 AM
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/A-Z]+$", var.report_schedule))
    error_message = "Report schedule must be a valid cron expression."
  }
}

variable "analytics_schedule" {
  description = "Cron schedule for automated compliance analytics processing"
  type        = string
  default     = "0 6 * * *"  # Daily at 6:00 AM
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/A-Z]+$", var.analytics_schedule))
    error_message = "Analytics schedule must be a valid cron expression."
  }
}

variable "document_processor_type" {
  description = "Type of Document AI processor for compliance documents"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "CONTRACT_PROCESSOR", 
      "DOCUMENT_OCR_PROCESSOR",
      "INVOICE_PROCESSOR"
    ], var.document_processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

variable "storage_class" {
  description = "Default storage class for compliance document storage"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE", 
      "COLDLINE",
      "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning for compliance document storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to compliance storage buckets"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.cloud_function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540  # 9 minutes (maximum for HTTP functions)
  
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "compliance-reporting"
    ManagedBy   = "terraform"
    Purpose     = "regulatory-compliance"
    CostCenter  = "security"
  }
}