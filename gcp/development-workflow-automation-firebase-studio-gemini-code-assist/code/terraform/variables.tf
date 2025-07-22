# Core project configuration
variable "project_id" {
  description = "The Google Cloud project ID for the development workflow automation"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens, and must start with a letter."
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
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Naming and tagging
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "ai-dev-workflow"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    application = "ai-dev-workflow"
    managed-by  = "terraform"
    recipe      = "development-workflow-automation"
  }
}

# Storage configuration
variable "storage_class" {
  description = "Storage class for the development artifacts bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_location" {
  description = "Location for the development artifacts bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Google Cloud Storage location."
  }
}

variable "bucket_retention_days" {
  description = "Number of days to retain objects in the development artifacts bucket"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_retention_days > 0 && var.bucket_retention_days <= 3650
    error_message = "Bucket retention days must be between 1 and 3650."
  }
}

# Cloud Functions configuration
variable "function_runtime" {
  description = "Runtime for the code review automation function"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311", "go119", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for the code review function (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the code review function (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

# Pub/Sub configuration
variable "message_retention_duration" {
  description = "Duration to retain messages in Pub/Sub topic (seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "subscription_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.subscription_ack_deadline >= 10 && var.subscription_ack_deadline <= 600
    error_message = "Subscription ack deadline must be between 10 and 600 seconds."
  }
}

# Firebase configuration
variable "firebase_location" {
  description = "Location for Firebase resources"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "asia-northeast1"
    ], var.firebase_location)
    error_message = "Firebase location must be a valid Firebase location."
  }
}

variable "enable_firebase_hosting" {
  description = "Enable Firebase Hosting for the application"
  type        = bool
  default     = true
}

# Monitoring and alerting
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# AI/ML configuration
variable "enable_vertex_ai" {
  description = "Enable Vertex AI for enhanced AI capabilities"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Gemini model to use for code assistance"
  type        = string
  default     = "gemini-2.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.5-flash"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported model."
  }
}

# Security configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage"
  type        = bool
  default     = true
}

variable "function_ingress_settings" {
  description = "Ingress settings for Cloud Functions"
  type        = string
  default     = "ALLOW_INTERNAL_ONLY"
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.function_ingress_settings)
    error_message = "Function ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

# Development workspace configuration
variable "workspace_machine_type" {
  description = "Machine type for development workspaces"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-highmem-2", "e2-highmem-4",
      "n2-standard-2", "n2-standard-4", "n2-highmem-2", "n2-highmem-4"
    ], var.workspace_machine_type)
    error_message = "Workspace machine type must be a valid Google Cloud machine type."
  }
}

variable "workspace_disk_size" {
  description = "Disk size for development workspaces (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.workspace_disk_size >= 50 && var.workspace_disk_size <= 1000
    error_message = "Workspace disk size must be between 50 and 1000 GB."
  }
}