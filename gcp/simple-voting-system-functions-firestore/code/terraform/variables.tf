# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
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

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "voting-system"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must be 4-22 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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

# Cloud Functions Configuration
variable "functions_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs16", "nodejs18", "nodejs20",
      "python39", "python310", "python311", "python312",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21",
      "dotnet3", "dotnet6", "dotnet8"
    ], var.functions_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

variable "functions_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.functions_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "functions_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.functions_timeout >= 1 && var.functions_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "functions_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.functions_max_instances >= 1 && var.functions_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database (should match region for optimal performance)"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or region location."
  }
}

variable "firestore_database_type" {
  description = "Type of Firestore database"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_database_type)
    error_message = "Database type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Security Configuration
variable "allow_unauthenticated_access" {
  description = "Whether to allow unauthenticated access to Cloud Functions"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain the same characters but don't need to start with a letter."
  }
}