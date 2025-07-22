# Input Variables for E-commerce Personalization Infrastructure
# This file defines all configurable parameters for the deployment

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
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "e-commerce-personalization"
    managed-by  = "terraform"
    environment = "dev"
  }
}

# Cloud Storage Configuration
variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "asia-east1",
      "asia-northeast1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid GCP location."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects are deleted"
  type        = number
  default     = 365
  validation {
    condition     = var.lifecycle_age_days > 0
    error_message = "Lifecycle age must be a positive number."
  }
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "nam5"
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "asia-southeast1", "us-central1", "us-east1",
      "us-east4", "us-west1", "us-west2", "europe-west1", "europe-west2", "europe-west3"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
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

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for Firestore"
  type        = bool
  default     = true
}

variable "enable_delete_protection" {
  description = "Enable delete protection for Firestore database"
  type        = bool
  default     = true
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs16", "nodejs18", "nodejs20", "python38", "python39", "python310", "python311",
      "go116", "go118", "go119", "go120", "go121", "java11", "java17", "dotnet3", "dotnet6"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout > 0 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of instances for Cloud Functions"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0
    error_message = "Min instances must be 0 or greater."
  }
}

variable "function_concurrency" {
  description = "Maximum concurrent requests per function instance"
  type        = number
  default     = 80
  validation {
    condition     = var.function_concurrency >= 1 && var.function_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# Retail API Configuration
variable "retail_catalog_name" {
  description = "Name for the Retail API catalog"
  type        = string
  default     = "default_catalog"
}

variable "retail_branch_name" {
  description = "Name for the Retail API branch"
  type        = string
  default     = "default_branch"
}

# Security Configuration
variable "function_ingress_settings" {
  description = "Ingress settings for Cloud Functions"
  type        = string
  default     = "ALLOW_INTERNAL_ONLY"
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.function_ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

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

# Monitoring and Logging Configuration
variable "enable_logging" {
  description = "Enable logging for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Cost Optimization Configuration
variable "enable_lifecycle_management" {
  description = "Enable lifecycle management for Cloud Storage"
  type        = bool
  default     = true
}

variable "nearline_transition_days" {
  description = "Days after which objects transition to Nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.nearline_transition_days > 0
    error_message = "Nearline transition days must be positive."
  }
}

variable "coldline_transition_days" {
  description = "Days after which objects transition to Coldline storage"
  type        = number
  default     = 90
  validation {
    condition     = var.coldline_transition_days > 0
    error_message = "Coldline transition days must be positive."
  }
}

# Random Suffix Configuration
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10."
  }
}