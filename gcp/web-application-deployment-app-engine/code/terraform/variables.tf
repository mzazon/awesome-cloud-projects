# Input variables for the App Engine web application deployment
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for App Engine application"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west6",
      "asia-northeast1", "asia-south1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid App Engine region."
  }
}

variable "application_name" {
  description = "Name of the web application"
  type        = string
  default     = "flask-webapp"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.application_name))
    error_message = "Application name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "app_engine_runtime" {
  description = "Runtime environment for App Engine application"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20", "java11", "java17", "go119", "go120", "go121"
    ], var.app_engine_runtime)
    error_message = "Runtime must be a supported App Engine runtime version."
  }
}

variable "min_instances" {
  description = "Minimum number of instances for automatic scaling"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "max_instances" {
  description = "Maximum number of instances for automatic scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for automatic scaling (0.0 to 1.0)"
  type        = number
  default     = 0.6
  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 1.0
    error_message = "Target CPU utilization must be between 0.0 and 1.0."
  }
}

variable "environment_variables" {
  description = "Environment variables to set in the App Engine application"
  type        = map(string)
  default = {
    FLASK_ENV = "production"
  }
}

variable "source_directory" {
  description = "Local directory containing the application source code"
  type        = string
  default     = "${path.root}/app"
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "web-application-deployment"
    ManagedBy   = "terraform"
  }
}

variable "deletion_policy" {
  description = "Deletion policy for App Engine application (ABANDON or DELETE)"
  type        = string
  default     = "ABANDON"
  validation {
    condition     = contains(["ABANDON", "DELETE"], var.deletion_policy)
    error_message = "Deletion policy must be either 'ABANDON' or 'DELETE'."
  }
}