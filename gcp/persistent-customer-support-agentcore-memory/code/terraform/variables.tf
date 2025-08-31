# Variables for GCP Persistent AI Customer Support with Agent Engine Memory
# Terraform Infrastructure Configuration

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
      "asia-southeast1", "asia-northeast1", "asia-east1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports required services."
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

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "ai-support"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "firestore_location" {
  description = "Location for Firestore database (must be a multi-region or regional location)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west3", "asia-northeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "memory_retrieval_function_config" {
  description = "Configuration for the memory retrieval Cloud Function"
  type = object({
    memory_mb                = optional(number, 256)
    timeout_seconds         = optional(number, 60)
    max_instances          = optional(number, 100)
    min_instances          = optional(number, 0)
    available_cpu          = optional(string, "1")
    ingress_settings       = optional(string, "ALLOW_ALL")
    entry_point           = optional(string, "retrieve_memory")
    runtime               = optional(string, "python311")
  })
  default = {}
}

variable "chat_function_config" {
  description = "Configuration for the main AI chat Cloud Function"
  type = object({
    memory_mb                = optional(number, 512)
    timeout_seconds         = optional(number, 300)
    max_instances          = optional(number, 100)
    min_instances          = optional(number, 0)
    available_cpu          = optional(string, "1")
    ingress_settings       = optional(string, "ALLOW_ALL")
    entry_point           = optional(string, "support_chat")
    runtime               = optional(string, "python311")
  })
  default = {}
}

variable "vertex_ai_config" {
  description = "Configuration for Vertex AI model"
  type = object({
    model_name           = optional(string, "gemini-1.5-flash")
    max_output_tokens    = optional(number, 1024)
    temperature          = optional(number, 0.7)
    top_p                = optional(number, 0.8)
  })
  default = {}
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "ai-customer-support"
    environment = "development"
    managed_by  = "terraform"
  }
}

variable "create_service_account" {
  description = "Whether to create a dedicated service account for the functions"
  type        = bool
  default     = true
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to Cloud Functions (not recommended for production)"
  type        = bool
  default     = true
}

variable "cors_config" {
  description = "CORS configuration for Cloud Functions"
  type = object({
    allow_origins      = optional(list(string), ["*"])
    allow_methods      = optional(list(string), ["POST", "OPTIONS"])
    allow_headers      = optional(list(string), ["Content-Type", "Authorization"])
    max_age_seconds    = optional(number, 3600)
  })
  default = {}
}

variable "function_source_directory" {
  description = "Directory containing the Cloud Function source code"
  type        = string
  default     = "./functions"
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and Logging for the functions"
  type        = bool
  default     = true
}

variable "enable_vpc_connector" {
  description = "Whether to create and use a VPC connector for Cloud Functions"
  type        = bool
  default     = false
}

variable "vpc_connector_config" {
  description = "Configuration for VPC connector if enabled"
  type = object({
    name          = optional(string, "ai-support-connector")
    ip_cidr_range = optional(string, "10.8.0.0/28")
    network       = optional(string, "default")
  })
  default = {}
}