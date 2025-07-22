# Project and Location Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "location" {
  description = "The location for Document AI processor (us or eu)"
  type        = string
  default     = "us"
  validation {
    condition     = contains(["us", "eu"], var.location)
    error_message = "Location must be either 'us' or 'eu'."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "doc-intelligence"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# Document AI Configuration
variable "processor_display_name" {
  description = "Display name for the Document AI processor"
  type        = string
  default     = "invoice-processor"
}

variable "processor_type" {
  description = "Type of Document AI processor"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "OCR_PROCESSOR",
      "INVOICE_PROCESSOR",
      "RECEIPT_PROCESSOR",
      "CONTRACT_PROCESSOR"
    ], var.processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE",
      "COLDLINE",
      "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which to delete objects (0 to disable)"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age >= 0 && var.bucket_lifecycle_age <= 365
    error_message = "Bucket lifecycle age must be between 0 and 365 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "processing_ack_deadline" {
  description = "Acknowledgment deadline for processing subscription (in seconds)"
  type        = number
  default     = 600
  validation {
    condition     = var.processing_ack_deadline >= 10 && var.processing_ack_deadline <= 600
    error_message = "Processing ack deadline must be between 10 and 600 seconds."
  }
}

variable "results_ack_deadline" {
  description = "Acknowledgment deadline for results subscription (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.results_ack_deadline >= 10 && var.results_ack_deadline <= 600
    error_message = "Results ack deadline must be between 10 and 600 seconds."
  }
}

# Cloud Functions Configuration
variable "processing_function_memory" {
  description = "Memory allocation for the document processing function (in MB)"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.processing_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "processing_function_timeout" {
  description = "Timeout for the document processing function (in seconds)"
  type        = number
  default     = 540
  validation {
    condition     = var.processing_function_timeout >= 60 && var.processing_function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "consumer_function_memory" {
  description = "Memory allocation for the results consumer function (in MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.consumer_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "consumer_function_timeout" {
  description = "Timeout for the results consumer function (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.consumer_function_timeout >= 60 && var.consumer_function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 100
    error_message = "Function max instances must be between 1 and 100."
  }
}

# Firestore Configuration
variable "firestore_database_type" {
  description = "Firestore database type"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_database_type)
    error_message = "Firestore database type must be FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

variable "firestore_location_id" {
  description = "Firestore database location"
  type        = string
  default     = "nam5"
  validation {
    condition = can(regex("^(nam5|eur3|asia-northeast1|us-central1|us-east1|us-east4|us-west1|us-west2|us-west3|us-west4)$", var.firestore_location_id))
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

# Security and IAM Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "doc-intelligence"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain the same characters."
  }
}

# API Services Configuration
variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "api_services" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "documentai.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]
}