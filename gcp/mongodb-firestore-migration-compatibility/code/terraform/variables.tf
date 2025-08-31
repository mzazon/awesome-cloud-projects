# Variables for MongoDB to Firestore migration infrastructure

variable "project_id" {
  description = "The Google Cloud project ID for the migration infrastructure"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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

variable "zone" {
  description = "The Google Cloud zone for resources requiring zone specification"
  type        = string
  default     = "us-central1-a"
}

variable "firestore_location" {
  description = "Location for Firestore database (must be a valid Firestore location)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-northeast1", "asia-northeast2", "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or region location."
  }
}

variable "mongodb_connection_string" {
  description = "MongoDB connection string for migration (will be stored in Secret Manager)"
  type        = string
  sensitive   = true
  
  validation {
    condition     = can(regex("^mongodb://", var.mongodb_connection_string))
    error_message = "MongoDB connection string must start with 'mongodb://'."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "migration_function_memory" {
  description = "Memory allocation for migration Cloud Function (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.migration_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "migration_function_timeout" {
  description = "Timeout for migration Cloud Function (seconds)"
  type        = number
  default     = 540
  
  validation {
    condition     = var.migration_function_timeout >= 60 && var.migration_function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "api_function_memory" {
  description = "Memory allocation for API compatibility Cloud Function (MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.api_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "api_function_timeout" {
  description = "Timeout for API compatibility Cloud Function (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.api_function_timeout >= 60 && var.api_function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "cloud_build_service_account_roles" {
  description = "Additional IAM roles to grant to Cloud Build service account"
  type        = list(string)
  default = [
    "roles/cloudfunctions.invoker",
    "roles/secretmanager.secretAccessor",
    "roles/datastore.user"
  ]
}

variable "resource_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "mongodb-firestore-migration"
    managed-by  = "terraform"
  }
}