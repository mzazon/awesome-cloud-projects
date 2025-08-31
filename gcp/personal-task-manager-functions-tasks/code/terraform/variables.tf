# Variable definitions for GCP Personal Task Manager infrastructure
# These variables allow customization of the deployment while maintaining
# reasonable defaults for quick setup and testing

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
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
  description = "Name of the Cloud Function for task management"
  type        = string
  default     = "task-manager"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "function_description" {
  description = "Description for the Cloud Function"
  type        = string
  default     = "Serverless API for managing Google Tasks"
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be one of the supported versions."
  }
}

variable "service_account_name" {
  description = "Name of the service account for the Cloud Function"
  type        = string
  default     = "task-manager-sa"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Task Manager Service Account"
}

variable "enable_public_access" {
  description = "Whether to allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "task-manager"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : 
      can(regex("^[a-z][a-z0-9_-]*$", key)) && 
      can(regex("^[a-z0-9_-]*$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "source_code_path" {
  description = "Path to the source code directory (relative to this Terraform configuration)"
  type        = string
  default     = "../function-source"
}

variable "enable_vpc_connector" {
  description = "Whether to use VPC connector for the Cloud Function"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector (if enabled)"
  type        = string
  default     = ""
}

variable "environment_variables" {
  description = "Environment variables for the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances (for reduced cold starts)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}