# Variables for Currency Converter API with Cloud Functions
# Define all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function that handles currency conversion"
  type        = string
  default     = "currency-converter"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "secret_name" {
  description = "Name for the Secret Manager secret storing the exchange rate API key"
  type        = string
  default     = null
  validation {
    condition     = var.secret_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.secret_name))
    error_message = "Secret name must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "exchange_api_key" {
  description = "The API key for the exchange rate service (e.g., fixer.io). This will be stored securely in Secret Manager."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.exchange_api_key) > 0
    error_message = "Exchange API key must not be empty. Get a free API key from https://fixer.io"
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
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

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime version."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated invocations of the Cloud Function"
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
  description = "Maximum number of function instances that can be created"
  type        = number
  default     = 100
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "currency-converter"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}