# Input variables for the tax calculator API infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "firestore_location_id" {
  description = "The location ID for the Firestore database (multi-region or regional)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west1", "europe-west1", "asia-east1"
    ], var.firestore_location_id)
    error_message = "Firestore location must be a valid location ID."
  }
}

variable "function_name_prefix" {
  description = "Prefix for Cloud Function names to ensure uniqueness"
  type        = string
  default     = "tax-calculator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name_prefix))
    error_message = "Function name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "calculator_function_memory" {
  description = "Memory allocation for the tax calculator function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.calculator_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "history_function_memory" {
  description = "Memory allocation for the calculation history function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.history_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "calculator_function_timeout" {
  description = "Timeout for the tax calculator function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.calculator_function_timeout >= 1 && var.calculator_function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "history_function_timeout" {
  description = "Timeout for the calculation history function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.history_function_timeout >= 1 && var.history_function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "calculator_max_instances" {
  description = "Maximum number of instances for the tax calculator function"
  type        = number
  default     = 10
  
  validation {
    condition     = var.calculator_max_instances >= 1 && var.calculator_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "history_max_instances" {
  description = "Maximum number of instances for the calculation history function"
  type        = number
  default     = 5
  
  validation {
    condition     = var.history_max_instances >= 1 && var.history_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "Minimum number of instances for Cloud Functions (0 for scale-to-zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python312"
  
  validation {
    condition     = contains(["python38", "python39", "python310", "python311", "python312"], var.python_runtime)
    error_message = "Python runtime must be one of: python38, python39, python310, python311, or python312."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the Cloud Functions"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "tax-calculator-api"
    managed-by  = "terraform"
    environment = "dev"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must follow Google Cloud naming conventions."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "delete_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = false
}