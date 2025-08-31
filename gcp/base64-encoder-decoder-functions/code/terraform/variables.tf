# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# PROJECT CONFIGURATION
# ==============================================================================

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

# ==============================================================================
# NAMING CONFIGURATION
# ==============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must be lowercase alphanumeric with hyphens, starting with letter."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "base64"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase alphanumeric with hyphens, starting with letter."
  }
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ==============================================================================

variable "function_runtime" {
  description = "Runtime for Cloud Functions (Python version)"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.function_memory)
    error_message = "Function memory must be a valid memory allocation (128M, 256M, 512M, 1G, 2G, 4G, 8G)."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances (0 for serverless scaling)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "storage_location" {
  description = "Location for the Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", 
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Google Cloud location."
  }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "enable_public_access" {
  description = "Enable public access to Cloud Functions (unauthenticated invocations)"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed CORS origins for Cloud Functions"
  type        = list(string)
  default     = ["*"]
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

# ==============================================================================
# LABELS AND TAGS
# ==============================================================================

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "base64-functions"
    managed-by  = "terraform"
    use-case    = "data-transformation"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must be lowercase alphanumeric with underscores and hyphens."
  }
}

# ==============================================================================
# ENABLE/DISABLE FEATURES
# ==============================================================================

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = false
}

variable "enable_lifecycle" {
  description = "Enable lifecycle management on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects are deleted (lifecycle management)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days >= 1
    error_message = "Lifecycle age must be at least 1 day."
  }
}