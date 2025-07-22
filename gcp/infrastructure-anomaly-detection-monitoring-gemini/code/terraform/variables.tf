# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini
# Terraform variable definitions

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region where Vertex AI is available."
  }
}

variable "zone" {
  description = "The Google Cloud zone where compute resources will be created"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "anomaly-detection"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-21 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_test_infrastructure" {
  description = "Whether to create test infrastructure (VM instance) for monitoring validation"
  type        = bool
  default     = true
}

variable "test_instance_machine_type" {
  description = "Machine type for the test VM instance"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.test_instance_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.cloud_function_memory >= 128 && var.cloud_function_memory <= 8192
    error_message = "Cloud Function memory must be between 128MB and 8192MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 540
  
  validation {
    condition     = var.cloud_function_timeout >= 60 && var.cloud_function_timeout <= 3600
    error_message = "Cloud Function timeout must be between 60 and 3600 seconds."
  }
}

variable "cloud_function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_function_max_instances >= 1 && var.cloud_function_max_instances <= 1000
    error_message = "Cloud Function max instances must be between 1 and 1000."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription (in seconds)"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in format '604800s' (seconds)."
  }
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription (in seconds)"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Pub/Sub ack deadline must be between 10 and 600 seconds."
  }
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for anomaly detection (0.0 to 1.0)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.cpu_threshold >= 0.0 && var.cpu_threshold <= 1.0
    error_message = "CPU threshold must be between 0.0 and 1.0."
  }
}

variable "notification_email" {
  description = "Email address for anomaly notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for anomaly analysis"
  type        = string
  default     = "gemini-2.0-flash-exp"
  
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.0-flash-exp"
    ], var.gemini_model)
    error_message = "Gemini model must be a valid available model."
  }
}

variable "enable_ops_agent" {
  description = "Whether to install Ops Agent on test instances for enhanced monitoring"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "infrastructure-anomaly-detection"
    environment = "demo"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Labels must follow Google Cloud naming conventions."
  }
}