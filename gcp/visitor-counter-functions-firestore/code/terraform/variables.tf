# Project configuration variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Cloud Function configuration variables
variable "function_name" {
  description = "Name of the Cloud Function for the visitor counter"
  type        = string
  default     = "visit-counter"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 1-63 characters long."
  }
}

variable "function_description" {
  description = "Description for the Cloud Function"
  type        = string
  default     = "Serverless visitor counter using Cloud Functions and Firestore"
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python38", "python39", "python310", "python311", "python312",
      "go119", "go120", "go121", "java11", "java17", "dotnet6", "ruby30", "ruby32"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

# Firestore configuration variables
variable "firestore_location" {
  description = "Location for the Firestore database (must be a multi-region or regional location)"
  type        = string
  default     = "nam5" # North America multi-region
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "asia-south1", "asia-southeast1",
      "australia-southeast1", "europe-west1", "europe-west2", "europe-west3",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "firestore_type" {
  description = "Type of Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_type)
    error_message = "Firestore type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Security and access configuration
variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the function"
  type        = list(string)
  default     = ["*"]
}

# Resource naming and tagging
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 1-16 characters long."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "visitor-counter"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, and be 1-63 characters long."
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens, and be 0-63 characters long."
  }
}

# Optional service enablement
variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable for the project"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com"
  ]
}