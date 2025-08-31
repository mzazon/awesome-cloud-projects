# Project and location variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Pub/Sub configuration variables
variable "topic_name" {
  description = "Name of the Pub/Sub topic for file notifications"
  type        = string
  default     = "file-upload-notifications"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.topic_name))
    error_message = "Topic name must start with a letter, contain only letters, numbers, hyphens, and underscores, and end with a letter or number."
  }
}

variable "subscription_name" {
  description = "Name of the Pub/Sub subscription for consuming messages"
  type        = string
  default     = "file-processor"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.subscription_name))
    error_message = "Subscription name must start with a letter, contain only letters, numbers, hyphens, and underscores, and end with a letter or number."
  }
}

variable "ack_deadline_seconds" {
  description = "The maximum time a subscriber has to acknowledge a message (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages (in seconds, max 7 days)"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '604800s')."
  }
}

# Cloud Storage configuration variables
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with project ID and random string)"
  type        = string
  default     = "file-uploads"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "The default storage class for objects in the bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for simplified IAM management"
  type        = bool
  default     = true
}

# Notification configuration variables
variable "notification_event_types" {
  description = "List of event types that trigger notifications"
  type        = list(string)
  default     = ["OBJECT_FINALIZE", "OBJECT_DELETE"]
  
  validation {
    condition = alltrue([
      for event in var.notification_event_types :
      contains(["OBJECT_FINALIZE", "OBJECT_DELETE", "OBJECT_METADATA_UPDATE", "OBJECT_ARCHIVE"], event)
    ])
    error_message = "Event types must be one of: OBJECT_FINALIZE, OBJECT_DELETE, OBJECT_METADATA_UPDATE, OBJECT_ARCHIVE."
  }
}

variable "notification_payload_format" {
  description = "The desired format of the notification payload"
  type        = string
  default     = "JSON_API_V1"
  
  validation {
    condition = contains([
      "JSON_API_V1", "NONE"
    ], var.notification_payload_format)
    error_message = "Payload format must be either JSON_API_V1 or NONE."
  }
}

# Resource labeling and tagging
variable "labels" {
  description = "A map of labels to assign to resources"
  type        = map(string)
  default = {
    environment = "development"
    purpose     = "file-processing"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# API services to enable
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "pubsub.googleapis.com"
  ]
}