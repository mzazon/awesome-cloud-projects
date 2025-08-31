# Smart Parking Management - Terraform Variables
# Define all configurable parameters for the infrastructure deployment

# ================================================================================
# PROJECT AND LOCATION VARIABLES
# ================================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment (affects latency and compliance)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-southeast1", "asia-northeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Firestore support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# ================================================================================
# RESOURCE NAMING VARIABLES
# ================================================================================

variable "project_name" {
  description = "Descriptive name for the project used in resource naming"
  type        = string
  default     = "smart-parking"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (affects resource naming and configurations)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for globally unique resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

# ================================================================================
# PUB/SUB CONFIGURATION VARIABLES
# ================================================================================

variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic that receives parking sensor data"
  type        = string
  default     = "parking-events"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-._~%+]{2,254}$", var.pubsub_topic_name))
    error_message = "Topic name must be 3-255 characters and contain only letters, numbers, dashes, periods, underscores, tildes, percent signs, and plus signs."
  }
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription for parking data processing"
  type        = string
  default     = "parking-processing"
}

variable "pubsub_message_retention_duration" {
  description = "How long to retain unacknowledged messages in Pub/Sub (in seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub messages (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# ================================================================================
# CLOUD FUNCTIONS CONFIGURATION VARIABLES
# ================================================================================

variable "parking_processor_function_name" {
  description = "Name for the Cloud Function that processes parking sensor data"
  type        = string
  default     = "process-parking-data"
}

variable "parking_api_function_name" {
  description = "Name for the Cloud Function that provides the parking management API"
  type        = string
  default     = "parking-management-api"
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions (Node.js version)"
  type        = string
  default     = "nodejs20"
  validation {
    condition     = contains(["nodejs18", "nodejs20"], var.function_runtime)
    error_message = "Function runtime must be nodejs18 or nodejs20."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
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

variable "function_max_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

# ================================================================================
# FIRESTORE CONFIGURATION VARIABLES
# ================================================================================

variable "firestore_database_type" {
  description = "Type of Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_database_type)
    error_message = "Database type must be FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

variable "firestore_location_id" {
  description = "Location for Firestore database (should match or be compatible with region)"
  type        = string
  default     = "us-central"
}

variable "parking_spaces_collection" {
  description = "Name of the Firestore collection for parking space documents"
  type        = string
  default     = "parking_spaces"
}

variable "parking_zones_collection" {
  description = "Name of the Firestore collection for parking zone aggregations"
  type        = string
  default     = "parking_zones"
}

# ================================================================================
# MAPS PLATFORM CONFIGURATION VARIABLES
# ================================================================================

variable "maps_api_key_name" {
  description = "Display name for the Google Maps Platform API key"
  type        = string
  default     = "Smart Parking Maps API"
}

variable "enable_maps_api_restrictions" {
  description = "Whether to enable API restrictions for Maps Platform API key"
  type        = bool
  default     = true
}

variable "maps_allowed_referrers" {
  description = "List of allowed referrers for Maps API key (HTTP restrictions)"
  type        = list(string)
  default     = ["*"] # Allow all referrers for development; restrict in production
}

# ================================================================================
# IAM AND SECURITY VARIABLES
# ================================================================================

variable "mqtt_service_account_name" {
  description = "Name for the service account used by MQTT broker for Pub/Sub publishing"
  type        = string
  default     = "mqtt-pubsub-publisher"
}

variable "mqtt_service_account_display_name" {
  description = "Display name for the MQTT service account"
  type        = string
  default     = "MQTT to Pub/Sub Publisher"
}

variable "create_service_account_key" {
  description = "Whether to create a service account key for MQTT broker authentication"
  type        = bool
  default     = true
}

variable "enable_api_authentication" {
  description = "Whether to enable authentication for the parking management API"
  type        = bool
  default     = false # Set to true for production deployments
}

# ================================================================================
# MONITORING AND LOGGING VARIABLES
# ================================================================================

variable "enable_cloud_logging" {
  description = "Whether to enable Cloud Logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for infrastructure metrics"
  type        = bool
  default     = true
}

# ================================================================================
# COST OPTIMIZATION VARIABLES
# ================================================================================

variable "enable_apis_on_create" {
  description = "Whether to automatically enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "delete_default_resources" {
  description = "Whether to delete default network and other resources to reduce costs"
  type        = bool
  default     = false
}

# ================================================================================
# TAGGING AND LABELING VARIABLES
# ================================================================================

variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    project     = "smart-parking"
    environment = "development"
    team        = "infrastructure"
    component   = "iot-parking"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

# ================================================================================
# ADVANCED CONFIGURATION VARIABLES
# ================================================================================

variable "enable_private_google_access" {
  description = "Whether to enable Private Google Access for VPC networks"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "backup_retention_policy" {
  description = "Backup retention policy for Firestore (in days)"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_policy >= 1 && var.backup_retention_policy <= 365
    error_message = "Backup retention policy must be between 1 and 365 days."
  }
}