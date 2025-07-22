# Smart City Data Processing Infrastructure
# Variable definitions for configurable deployment parameters

# Core Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where regional resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone where zonal resources will be created"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Naming and Labeling
variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for naming resources to ensure uniqueness"
  type        = string
  default     = "smart-city"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project      = "smart-city-analytics"
    use-case     = "iot-data-processing"
    department   = "urban-planning"
    cost-center  = "infrastructure"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# BigQuery Configuration
variable "bigquery_dataset_id" {
  description = "The BigQuery dataset ID for smart city analytics"
  type        = string
  default     = "smart_city_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_id))
    error_message = "BigQuery dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_location" {
  description = "The location for BigQuery dataset (can be regional or multi-regional)"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "us-central1", "us-east1", "us-west1", "europe-west1", "asia-southeast1"], var.bigquery_location)
    error_message = "BigQuery location must be a valid location (US, EU, or specific region)."
  }
}

variable "bigquery_default_table_expiration_ms" {
  description = "Default table expiration in milliseconds (0 for no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.bigquery_default_table_expiration_ms >= 0
    error_message = "Table expiration must be 0 or a positive number."
  }
}

variable "bigquery_delete_contents_on_destroy" {
  description = "Whether to delete all tables when destroying the BigQuery dataset"
  type        = bool
  default     = false
}

# Cloud Storage Configuration
variable "storage_bucket_location" {
  description = "The location for Cloud Storage buckets"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "ASIA", "us-central1", "us-east1", "europe-west1", "asia-southeast1"], var.storage_bucket_location)
    error_message = "Storage location must be a valid location (US, EU, ASIA, or specific region)."
  }
}

variable "storage_bucket_storage_class" {
  description = "The default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_bucket_versioning" {
  description = "Whether to enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_nearline" {
  description = "Age in days after which objects transition to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.storage_lifecycle_age_nearline > 0 && var.storage_lifecycle_age_nearline <= 365
    error_message = "NEARLINE transition age must be between 1 and 365 days."
  }
}

variable "storage_lifecycle_age_coldline" {
  description = "Age in days after which objects transition to COLDLINE storage"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age_coldline > 0 && var.storage_lifecycle_age_coldline <= 365
    error_message = "COLDLINE transition age must be between 1 and 365 days."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (e.g., 7d, 24h)"
  type        = string
  default     = "604800s" # 7 days in seconds
  validation {
    condition     = can(regex("^[0-9]+[smhd]?$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be a valid duration (e.g., 604800s, 7d, 24h)."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Sensor Data Topic Configuration
variable "sensor_topics" {
  description = "Configuration for different sensor data Pub/Sub topics"
  type = map(object({
    name        = string
    description = string
    schema = optional(object({
      type       = string
      definition = string
    }))
  }))
  default = {
    traffic = {
      name        = "traffic-sensor-data"
      description = "Real-time traffic sensor data from city intersections and highways"
      schema = {
        type       = "AVRO"
        definition = jsonencode({
          type = "record"
          name = "TrafficSensorData"
          fields = [
            { name = "sensor_id", type = "string" },
            { name = "timestamp", type = "long" },
            { name = "location", type = "string" },
            { name = "vehicle_count", type = ["null", "int"], default = null },
            { name = "avg_speed", type = ["null", "double"], default = null },
            { name = "congestion_level", type = ["null", "string"], default = null },
            { name = "weather_conditions", type = ["null", "string"], default = null }
          ]
        })
      }
    }
    air_quality = {
      name        = "air-quality-data"
      description = "Real-time air quality measurements from environmental sensors"
      schema = {
        type       = "AVRO"
        definition = jsonencode({
          type = "record"
          name = "AirQualityData"
          fields = [
            { name = "sensor_id", type = "string" },
            { name = "timestamp", type = "long" },
            { name = "location", type = "string" },
            { name = "pm25", type = ["null", "double"], default = null },
            { name = "pm10", type = ["null", "double"], default = null },
            { name = "ozone", type = ["null", "double"], default = null },
            { name = "no2", type = ["null", "double"], default = null },
            { name = "air_quality_index", type = ["null", "int"], default = null }
          ]
        })
      }
    }
    energy = {
      name        = "energy-consumption-data"
      description = "Real-time energy consumption data from smart meters"
      schema = {
        type       = "AVRO"
        definition = jsonencode({
          type = "record"
          name = "EnergyConsumptionData"
          fields = [
            { name = "meter_id", type = "string" },
            { name = "timestamp", type = "long" },
            { name = "location", type = "string" },
            { name = "energy_usage_kwh", type = ["null", "double"], default = null },
            { name = "peak_demand", type = ["null", "double"], default = null },
            { name = "building_type", type = ["null", "string"], default = null },
            { name = "occupancy_rate", type = ["null", "double"], default = null }
          ]
        })
      }
    }
  }
}

# Service Account Configuration
variable "dataprep_service_account_id" {
  description = "Service account ID for Cloud Dataprep operations"
  type        = string
  default     = "dataprep-service-account"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.dataprep_service_account_id))
    error_message = "Service account ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "dataflow_service_account_id" {
  description = "Service account ID for Dataflow pipeline operations"
  type        = string
  default     = "dataflow-service-account"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.dataflow_service_account_id))
    error_message = "Service account ID must contain only lowercase letters, numbers, and hyphens."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Whether to enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Cost Control Configuration
variable "enable_cost_controls" {
  description = "Whether to enable cost control measures and budget alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 500
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

# Network and Security Configuration
variable "enable_private_google_access" {
  description = "Whether to enable Private Google Access for secure service communication"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Default allows all IPs - restrict in production
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., 10.0.0.0/8)."
  }
}

# Data Processing Configuration
variable "enable_real_time_processing" {
  description = "Whether to enable real-time stream processing with Dataflow"
  type        = bool
  default     = true
}

variable "dataflow_max_workers" {
  description = "Maximum number of workers for Dataflow jobs"
  type        = number
  default     = 10
  validation {
    condition     = var.dataflow_max_workers >= 1 && var.dataflow_max_workers <= 100
    error_message = "Dataflow max workers must be between 1 and 100."
  }
}

variable "enable_data_quality_monitoring" {
  description = "Whether to enable automated data quality monitoring and alerting"
  type        = bool
  default     = true
}