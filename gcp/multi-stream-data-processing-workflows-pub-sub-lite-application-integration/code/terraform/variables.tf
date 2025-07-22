# Variables for Multi-Stream Data Processing Workflows
# These variables allow customization of the infrastructure deployment
# while maintaining security and best practices

variable "project_id" {
  description = "Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Primary Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "throughput_capacity" {
  description = "Total Pub/Sub Lite throughput capacity in MiB/s (sum of all topic publish capacities)"
  type        = number
  default     = 9
  
  validation {
    condition     = var.throughput_capacity >= 1 && var.throughput_capacity <= 1000
    error_message = "Throughput capacity must be between 1 and 1000 MiB/s."
  }
}

variable "retention_days" {
  description = "Data retention period in days for BigQuery tables and Cloud Storage lifecycle"
  type        = number
  default     = 365
  
  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 3650
    error_message = "Retention days must be between 1 and 3650 days (10 years)."
  }
}

variable "dataset_location" {
  description = "BigQuery dataset location (multi-region or region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "us-west3", "us-west4", "europe-north1", "europe-west1", "europe-west2",
      "europe-west3", "europe-west4", "europe-west6", "asia-east1", "asia-east2",
      "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.notification_channels) <= 16
    error_message = "Cannot specify more than 16 notification channels."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alert policies"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable enhanced logging for debugging and audit purposes"
  type        = bool
  default     = true
}

variable "iot_topic_config" {
  description = "Configuration for IoT data stream topic"
  type = object({
    partitions            = number
    publish_capacity      = number
    subscribe_capacity    = number
    per_partition_gb      = number
    retention_days        = number
  })
  default = {
    partitions            = 4
    publish_capacity      = 4
    subscribe_capacity    = 8
    per_partition_gb      = 30
    retention_days        = 7
  }
  
  validation {
    condition = (
      var.iot_topic_config.partitions >= 1 && var.iot_topic_config.partitions <= 100 &&
      var.iot_topic_config.publish_capacity >= 1 && var.iot_topic_config.publish_capacity <= 1000 &&
      var.iot_topic_config.subscribe_capacity >= 1 && var.iot_topic_config.subscribe_capacity <= 1000 &&
      var.iot_topic_config.per_partition_gb >= 1 && var.iot_topic_config.per_partition_gb <= 1000 &&
      var.iot_topic_config.retention_days >= 1 && var.iot_topic_config.retention_days <= 365
    )
    error_message = "IoT topic configuration values must be within valid ranges."
  }
}

variable "app_events_topic_config" {
  description = "Configuration for application events stream topic"
  type = object({
    partitions            = number
    publish_capacity      = number
    subscribe_capacity    = number
    per_partition_gb      = number
    retention_days        = number
  })
  default = {
    partitions            = 2
    publish_capacity      = 2
    subscribe_capacity    = 4
    per_partition_gb      = 50
    retention_days        = 14
  }
  
  validation {
    condition = (
      var.app_events_topic_config.partitions >= 1 && var.app_events_topic_config.partitions <= 100 &&
      var.app_events_topic_config.publish_capacity >= 1 && var.app_events_topic_config.publish_capacity <= 1000 &&
      var.app_events_topic_config.subscribe_capacity >= 1 && var.app_events_topic_config.subscribe_capacity <= 1000 &&
      var.app_events_topic_config.per_partition_gb >= 1 && var.app_events_topic_config.per_partition_gb <= 1000 &&
      var.app_events_topic_config.retention_days >= 1 && var.app_events_topic_config.retention_days <= 365
    )
    error_message = "App events topic configuration values must be within valid ranges."
  }
}

variable "system_logs_topic_config" {
  description = "Configuration for system logs stream topic"
  type = object({
    partitions            = number
    publish_capacity      = number
    subscribe_capacity    = number
    per_partition_gb      = number
    retention_days        = number
  })
  default = {
    partitions            = 3
    publish_capacity      = 3
    subscribe_capacity    = 6
    per_partition_gb      = 40
    retention_days        = 30
  }
  
  validation {
    condition = (
      var.system_logs_topic_config.partitions >= 1 && var.system_logs_topic_config.partitions <= 100 &&
      var.system_logs_topic_config.publish_capacity >= 1 && var.system_logs_topic_config.publish_capacity <= 1000 &&
      var.system_logs_topic_config.subscribe_capacity >= 1 && var.system_logs_topic_config.subscribe_capacity <= 1000 &&
      var.system_logs_topic_config.per_partition_gb >= 1 && var.system_logs_topic_config.per_partition_gb <= 1000 &&
      var.system_logs_topic_config.retention_days >= 1 && var.system_logs_topic_config.retention_days <= 365
    )
    error_message = "System logs topic configuration values must be within valid ranges."
  }
}

variable "dataflow_config" {
  description = "Configuration for Cloud Dataflow pipeline settings"
  type = object({
    max_workers           = number
    worker_machine_type   = string
    disk_size_gb         = number
    enable_streaming_engine = bool
  })
  default = {
    max_workers           = 4
    worker_machine_type   = "n1-standard-2"
    disk_size_gb         = 100
    enable_streaming_engine = true
  }
  
  validation {
    condition = (
      var.dataflow_config.max_workers >= 1 && var.dataflow_config.max_workers <= 1000 &&
      var.dataflow_config.disk_size_gb >= 10 && var.dataflow_config.disk_size_gb <= 1000 &&
      contains(["n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16", "n1-highmem-2", "n1-highmem-4", "n1-highmem-8"], var.dataflow_config.worker_machine_type)
    )
    error_message = "Dataflow configuration values must be within valid ranges and machine types."
  }
}

variable "bigquery_config" {
  description = "Configuration for BigQuery tables and performance optimization"
  type = object({
    enable_partition_filter = bool
    clustering_enabled      = bool
    streaming_buffer_size   = number
  })
  default = {
    enable_partition_filter = true
    clustering_enabled      = true
    streaming_buffer_size   = 1000
  }
  
  validation {
    condition = (
      var.bigquery_config.streaming_buffer_size >= 100 && var.bigquery_config.streaming_buffer_size <= 10000
    )
    error_message = "BigQuery streaming buffer size must be between 100 and 10,000 rows."
  }
}

variable "storage_lifecycle_config" {
  description = "Configuration for Cloud Storage lifecycle management"
  type = object({
    nearline_days  = number
    coldline_days  = number
    archive_days   = number
    enable_versioning = bool
  })
  default = {
    nearline_days  = 30
    coldline_days  = 90
    archive_days   = 180
    enable_versioning = true
  }
  
  validation {
    condition = (
      var.storage_lifecycle_config.nearline_days >= 1 && var.storage_lifecycle_config.nearline_days <= 365 &&
      var.storage_lifecycle_config.coldline_days >= var.storage_lifecycle_config.nearline_days &&
      var.storage_lifecycle_config.coldline_days <= 365 &&
      var.storage_lifecycle_config.archive_days >= var.storage_lifecycle_config.coldline_days &&
      var.storage_lifecycle_config.archive_days <= 365
    )
    error_message = "Storage lifecycle configuration must have increasing day values within valid ranges."
  }
}

variable "monitoring_config" {
  description = "Configuration for monitoring and alerting"
  type = object({
    message_backlog_threshold = number
    alert_duration_seconds   = number
    dashboard_refresh_interval = string
  })
  default = {
    message_backlog_threshold = 10000
    alert_duration_seconds   = 300
    dashboard_refresh_interval = "1m"
  }
  
  validation {
    condition = (
      var.monitoring_config.message_backlog_threshold >= 100 && var.monitoring_config.message_backlog_threshold <= 100000 &&
      var.monitoring_config.alert_duration_seconds >= 60 && var.monitoring_config.alert_duration_seconds <= 3600 &&
      contains(["30s", "1m", "5m", "10m", "30m", "1h"], var.monitoring_config.dashboard_refresh_interval)
    )
    error_message = "Monitoring configuration values must be within valid ranges."
  }
}

variable "security_config" {
  description = "Security configuration for the infrastructure"
  type = object({
    enable_uniform_bucket_level_access = bool
    enable_bigquery_cmek              = bool
    enable_pubsub_lite_cmek           = bool
    cmek_key_name                     = string
  })
  default = {
    enable_uniform_bucket_level_access = true
    enable_bigquery_cmek              = false
    enable_pubsub_lite_cmek           = false
    cmek_key_name                     = ""
  }
  
  validation {
    condition = (
      var.security_config.cmek_key_name == "" || 
      can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.security_config.cmek_key_name))
    )
    error_message = "CMEK key name must be empty or a valid Cloud KMS key resource name."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot specify more than 64 labels."
  }
}