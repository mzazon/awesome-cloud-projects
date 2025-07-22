# Input Variables for Document Processing Infrastructure
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Document AI."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "doc-proc"
  validation {
    condition     = length(var.resource_prefix) <= 10 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase alphanumeric with hyphens, max 10 characters."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (e.g., US, EU, ASIA)"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "ASIA"], var.bucket_location)
    error_message = "Bucket location must be one of: US, EU, ASIA."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "1Gi"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.cloud_run_memory))
    error_message = "Memory must be in format like '1Gi' or '512Mi'."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["1", "2", "4", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "How long Pub/Sub retains unacknowledged messages"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '604800s')."
  }
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "INVOICE_PROCESSOR", 
      "RECEIPT_PROCESSOR",
      "CONTRACT_PROCESSOR"
    ], var.document_ai_processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access on Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "cloud_run_ingress" {
  description = "Ingress settings for Cloud Run service"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.cloud_run_ingress)
    error_message = "Ingress must be a valid Cloud Run ingress setting."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    purpose     = "document-processing"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}