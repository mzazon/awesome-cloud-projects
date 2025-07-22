# =============================================================================
# PROJECT AND LOCATION VARIABLES
# =============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "europe-north1", "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# =============================================================================
# HEALTHCARE API VARIABLES
# =============================================================================

variable "dataset_id" {
  description = "ID for the healthcare dataset"
  type        = string
  default     = "medical-imaging-dataset"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "dicom_store_id" {
  description = "ID for the DICOM store"
  type        = string
  default     = "medical-dicom-store"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.dicom_store_id))
    error_message = "DICOM store ID must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "fhir_store_id" {
  description = "ID for the FHIR store"
  type        = string
  default     = "medical-fhir-store"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.fhir_store_id))
    error_message = "FHIR store ID must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "fhir_version" {
  description = "FHIR version for the FHIR store"
  type        = string
  default     = "R4"
  validation {
    condition     = contains(["DSTU2", "STU3", "R4"], var.fhir_version)
    error_message = "FHIR version must be one of: DSTU2, STU3, R4."
  }
}

# =============================================================================
# STORAGE VARIABLES
# =============================================================================

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "medical-imaging-bucket"
  validation {
    condition     = can(regex("^[a-z0-9._-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, dots, underscores, and hyphens."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# =============================================================================
# CLOUD FUNCTIONS VARIABLES
# =============================================================================

variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "medical-image-processor"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.function_name))
    error_message = "Function name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocated to the Cloud Function (in MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

# =============================================================================
# PUB/SUB VARIABLES
# =============================================================================

variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic"
  type        = string
  default     = "medical-image-processing"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.pubsub_topic_name))
    error_message = "Pub/Sub topic name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription"
  type        = string
  default     = "medical-image-processor-sub"
}

variable "subscription_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription (in seconds)"
  type        = number
  default     = 600
  validation {
    condition     = var.subscription_ack_deadline >= 10 && var.subscription_ack_deadline <= 600
    error_message = "Subscription acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# =============================================================================
# SERVICE ACCOUNT VARIABLES
# =============================================================================

variable "service_account_name" {
  description = "Name for the service account"
  type        = string
  default     = "medical-imaging-sa"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Medical Imaging Analysis Service Account"
}

# =============================================================================
# MONITORING VARIABLES
# =============================================================================

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the medical imaging pipeline"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

# =============================================================================
# REQUIRED APIS
# =============================================================================

variable "required_apis" {
  description = "List of required Google Cloud APIs"
  type        = list(string)
  default = [
    "healthcare.googleapis.com",
    "vision.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# =============================================================================
# SECURITY VARIABLES
# =============================================================================

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# =============================================================================
# RESOURCE NAMING
# =============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "medical-imaging"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# =============================================================================
# LABELS AND TAGS
# =============================================================================

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "medical-imaging-analysis"
    environment = "dev"
    managed-by  = "terraform"
    use-case    = "healthcare-ai"
  }
}