# Variables for Conversational AI Backend Infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports all required services."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the specified region"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
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

variable "function_memory" {
  description = "Memory allocation for main conversation processing function in MB"
  type        = number
  default     = 1024
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "history_function_memory" {
  description = "Memory allocation for conversation history function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.history_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "firestore_location" {
  description = "Location for Firestore database (must support Firestore in Native mode)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-northeast1", "asia-south1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must support native mode."
  }
}

variable "storage_class" {
  description = "Storage class for the conversation artifacts bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Age in days for bucket lifecycle policy (conversation data retention)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.bucket_lifecycle_age >= 1 && var.bucket_lifecycle_age <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the conversation artifacts bucket"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and custom metrics"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration on Cloud Functions"
  type        = list(string)
  default     = ["*"]
}

variable "min_instances" {
  description = "Minimum number of Cloud Function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Function instances for scaling"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "vertex_ai_region" {
  description = "Region for Vertex AI services (may differ from main region)"
  type        = string
  default     = ""
}

variable "conversation_retention_days" {
  description = "Number of days to retain conversation data before automated cleanup"
  type        = number
  default     = 90
  
  validation {
    condition     = var.conversation_retention_days >= 1 && var.conversation_retention_days <= 365
    error_message = "Conversation retention must be between 1 and 365 days."
  }
}

variable "enable_security_features" {
  description = "Enable additional security features like VPC connector and IAM bindings"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources for organization and billing"
  type        = map(string)
  default = {
    application = "conversational-ai"
    component   = "backend"
    managed-by  = "terraform"
  }
}