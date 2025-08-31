# Variables for GCP real-time fraud detection infrastructure
# Configure these values according to your environment and requirements

variable "project_id" {
  description = "Google Cloud Project ID for fraud detection system"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must be longer than 6 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Primary Google Cloud region for fraud detection resources"
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
  description = "Google Cloud zone within the specified region"
  type        = string
  default     = "us-central1-a"
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

# Spanner Configuration Variables
variable "spanner_instance_config" {
  description = "Spanner instance configuration for multi-region setup"
  type        = string
  default     = "nam3"
  validation {
    condition = contains([
      "nam3", "nam6", "nam-eur-asia1", "eur3", "eur5", 
      "asia1", "regional-us-central1", "regional-europe-west1", "regional-asia-east1"
    ], var.spanner_instance_config)
    error_message = "Spanner instance config must be a valid configuration."
  }
}

variable "spanner_processing_units" {
  description = "Number of processing units for Spanner instance (minimum 100)"
  type        = number
  default     = 100
  validation {
    condition     = var.spanner_processing_units >= 100 && var.spanner_processing_units <= 2000
    error_message = "Spanner processing units must be between 100 and 2000."
  }
}

variable "spanner_instance_display_name" {
  description = "Display name for the Spanner instance"
  type        = string
  default     = "Fraud Detection Database Instance"
}

variable "database_name" {
  description = "Name for the Spanner database"
  type        = string
  default     = "fraud-detection-db"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.database_name))
    error_message = "Database name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function (MB)"
  type        = string
  default     = "512M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions Gen2 memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
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
  description = "Minimum number of Cloud Function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub messages in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Pub/Sub ack deadline must be between 10 and 600 seconds."
  }
}

# Storage Configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_bucket_force_destroy" {
  description = "Force destroy storage bucket even if not empty"
  type        = bool
  default     = true
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI resources"
  type        = string
  default     = "us-central1"
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "fraud-detection"
    environment = "dev"
    team        = "security"
    cost-center = "engineering"
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "fraud-detection"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 12
    error_message = "Random suffix length must be between 4 and 12 characters."
  }
}

# Service Accounts
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for services"
  type        = bool
  default     = true
}

# API Services
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "spanner.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Security Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "enable_audit_logs" {
  description = "Enable audit logging for all services"
  type        = bool
  default     = true
}