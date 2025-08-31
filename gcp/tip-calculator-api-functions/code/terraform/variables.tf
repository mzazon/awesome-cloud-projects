# Input variables for the GCP tip calculator API infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for deploying the Cloud Function"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function (must be unique within the project)"
  type        = string
  default     = "tip-calculator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 1-63 characters long."
  }
}

variable "function_description" {
  description = "Description for the Cloud Function"
  type        = string
  default     = "Serverless tip calculator API for restaurant bills and bill splitting"
}

variable "runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312"
    ], var.runtime)
    error_message = "Runtime must be a supported Python runtime version."
  }
}

variable "memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.timeout >= 1 && var.timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "entry_point" {
  description = "The name of the function to execute within the source code"
  type        = string
  default     = "calculate_tip"
}

variable "source_dir" {
  description = "Path to the directory containing the function source code"
  type        = string
  default     = "../function-source"
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the function"
  type        = bool
  default     = true
}

variable "environment_variables" {
  description = "Environment variables to set for the function"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to the Cloud Function for organization and billing"
  type        = map(string)
  default = {
    environment = "demo"
    application = "tip-calculator"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = can([for k, v in var.labels : regex("^[a-z0-9_-]+$", k)])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "vpc_connector_egress_settings" {
  description = "VPC connector egress settings (ALL_TRAFFIC, PRIVATE_RANGES_ONLY)"
  type        = string
  default     = null
  
  validation {
    condition = var.vpc_connector_egress_settings == null || contains([
      "ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"
    ], var.vpc_connector_egress_settings)
    error_message = "VPC connector egress settings must be either ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }
}

variable "ingress_settings" {
  description = "Ingress settings for the function (ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB)"
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}