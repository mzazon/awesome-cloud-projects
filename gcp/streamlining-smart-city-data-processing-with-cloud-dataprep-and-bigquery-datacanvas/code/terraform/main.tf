# Smart City Data Processing Infrastructure
# Main Terraform configuration for GCP-based smart city analytics platform

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Naming conventions
  resource_suffix = random_id.suffix.hex
  resource_name_prefix = "${var.resource_prefix}-${var.environment}"
  
  # Common tags/labels
  common_labels = merge(var.labels, {
    environment     = var.environment
    terraform      = "true"
    resource-group = "smart-city-analytics"
    created-by     = "terraform"
    deployment-id  = local.resource_suffix
  })
  
  # Data lake folder structure
  data_lake_folders = [
    "raw-data/traffic/",
    "raw-data/air-quality/", 
    "raw-data/energy/",
    "processed-data/",
    "temp/",
    "staging/"
  ]
  
  # Service APIs required for the solution
  required_apis = [
    "bigquery.googleapis.com",
    "pubsub.googleapis.com", 
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "dataflow.googleapis.com",
    "dataprep.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.key
  
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled
resource "time_sleep" "api_enablement_delay" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

#------------------------------------------------------------------------------
# CLOUD STORAGE - Data Lake Infrastructure
#------------------------------------------------------------------------------

# Primary data lake bucket for smart city sensor data
resource "google_storage_bucket" "data_lake" {
  depends_on = [time_sleep.api_enablement_delay]
  
  name          = "${local.resource_name_prefix}-data-lake-${local.resource_suffix}"
  location      = var.storage_bucket_location
  storage_class = var.storage_bucket_storage_class
  
  # Enable uniform bucket-level access for consistent security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.storage_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_coldline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Prevent accidental deletion
  lifecycle_rule {
    condition {
      age                   = 2555 # ~7 years
      with_state           = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

# Create folder structure in the data lake bucket
resource "google_storage_bucket_object" "data_lake_folders" {
  for_each = toset(local.data_lake_folders)
  
  name   = each.value
  bucket = google_storage_bucket.data_lake.name
  content = " " # Empty content to create folder structure
  
  depends_on = [google_storage_bucket.data_lake]
}

# Bucket for temporary Dataflow processing files
resource "google_storage_bucket" "dataflow_temp" {
  depends_on = [time_sleep.api_enablement_delay]
  
  name          = "${local.resource_name_prefix}-dataflow-temp-${local.resource_suffix}"
  location      = var.storage_bucket_location
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  # Temporary files - shorter lifecycle
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

#------------------------------------------------------------------------------
# PUB/SUB - Real-time Data Ingestion
#------------------------------------------------------------------------------

# Pub/Sub schemas for structured data validation
resource "google_pubsub_schema" "sensor_schemas" {
  for_each = {
    for topic_key, config in var.sensor_topics : topic_key => config
    if config.schema != null
  }
  
  depends_on = [time_sleep.api_enablement_delay]
  
  name       = "${local.resource_name_prefix}-${each.key}-schema-${local.resource_suffix}"
  type       = each.value.schema.type
  definition = each.value.schema.definition
}

# Pub/Sub topics for different sensor data types
resource "google_pubsub_topic" "sensor_topics" {
  for_each = var.sensor_topics
  
  depends_on = [time_sleep.api_enablement_delay]
  
  name = "${local.resource_name_prefix}-${each.value.name}-${local.resource_suffix}"
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Schema validation (if schema is configured)
  dynamic "schema_settings" {
    for_each = each.value.schema != null ? [1] : []
    content {
      schema   = google_pubsub_schema.sensor_schemas[each.key].id
      encoding = "JSON"
    }
  }
  
  labels = merge(local.common_labels, {
    sensor-type = each.key
    data-source = "iot-sensors"
  })
}

# Pub/Sub subscriptions for data processing pipelines
resource "google_pubsub_subscription" "sensor_subscriptions" {
  for_each = var.sensor_topics
  
  name  = "${local.resource_name_prefix}-${each.key}-processing-sub-${local.resource_suffix}"
  topic = google_pubsub_topic.sensor_topics[each.key].name
  
  # Message acknowledgment configuration
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Dead letter queue configuration for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }
  
  # Retry policy for transient failures
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Enable message ordering for sequential processing
  enable_message_ordering = true
  
  labels = merge(local.common_labels, {
    sensor-type = each.key
    purpose     = "data-processing"
  })
}

# Dead letter topic for failed message handling
resource "google_pubsub_topic" "dead_letter_topic" {
  depends_on = [time_sleep.api_enablement_delay]
  
  name = "${local.resource_name_prefix}-dead-letters-${local.resource_suffix}"
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
}

#------------------------------------------------------------------------------
# BIGQUERY - Analytics Data Warehouse
#------------------------------------------------------------------------------

# BigQuery dataset for smart city analytics
resource "google_bigquery_dataset" "smart_city_analytics" {
  depends_on = [time_sleep.api_enablement_delay]
  
  dataset_id                  = var.bigquery_dataset_id
  friendly_name              = "Smart City Analytics Data Warehouse"
  description                = "Centralized data warehouse for smart city IoT sensor data, analytics, and reporting"
  location                   = var.bigquery_location
  default_table_expiration_ms = var.bigquery_default_table_expiration_ms
  delete_contents_on_destroy = var.bigquery_delete_contents_on_destroy
  
  labels = local.common_labels
  
  # Access control for the dataset
  access {
    role          = "OWNER"
    user_by_email = google_service_account.dataprep_service_account.email
  }
  
  access {
    role          = "WRITER"
    user_by_email = google_service_account.dataflow_service_account.email
  }
  
  access {
    role   = "READER"
    special_group = "projectReaders"
  }
}

# Traffic sensors table
resource "google_bigquery_table" "traffic_sensors" {
  depends_on = [google_bigquery_dataset.smart_city_analytics]
  
  dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  table_id   = "traffic_sensors"
  
  description = "Real-time and historical traffic sensor data from city intersections and highways"
  
  # Partitioning for performance optimization
  time_partitioning {
    type                     = "DAY"
    field                   = "timestamp"
    require_partition_filter = false
  }
  
  # Clustering for query performance
  clustering = ["sensor_id", "congestion_level"]
  
  # Schema definition
  schema = jsonencode([
    {
      name = "sensor_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the traffic sensor"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the measurement was taken"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "NULLABLE"
      description = "Geographic location of the sensor (WKT format)"
    },
    {
      name = "vehicle_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of vehicles detected in the measurement period"
    },
    {
      name = "avg_speed"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average vehicle speed in km/h"
    },
    {
      name = "congestion_level"
      type = "STRING"
      mode = "NULLABLE"
      description = "Traffic congestion level (light, moderate, heavy)"
    },
    {
      name = "weather_conditions"
      type = "STRING"
      mode = "NULLABLE"
      description = "Weather conditions during measurement"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Timestamp when the data was processed"
    }
  ])
  
  labels = merge(local.common_labels, {
    data-type = "traffic-sensors"
  })
}

# Air quality sensors table
resource "google_bigquery_table" "air_quality_sensors" {
  depends_on = [google_bigquery_dataset.smart_city_analytics]
  
  dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  table_id   = "air_quality_sensors"
  
  description = "Real-time and historical air quality measurements from environmental sensors"
  
  time_partitioning {
    type                     = "DAY"
    field                   = "timestamp"
    require_partition_filter = false
  }
  
  clustering = ["sensor_id", "air_quality_index"]
  
  schema = jsonencode([
    {
      name = "sensor_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the air quality sensor"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the measurement was taken"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "NULLABLE"
      description = "Geographic location of the sensor (WKT format)"
    },
    {
      name = "pm25"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "PM2.5 particle concentration in μg/m³"
    },
    {
      name = "pm10"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "PM10 particle concentration in μg/m³"
    },
    {
      name = "ozone"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Ozone concentration in ppm"
    },
    {
      name = "no2"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Nitrogen dioxide concentration in ppb"
    },
    {
      name = "air_quality_index"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Calculated air quality index (0-500 scale)"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Timestamp when the data was processed"
    }
  ])
  
  labels = merge(local.common_labels, {
    data-type = "air-quality-sensors"
  })
}

# Energy consumption table
resource "google_bigquery_table" "energy_consumption" {
  depends_on = [google_bigquery_dataset.smart_city_analytics]
  
  dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  table_id   = "energy_consumption"
  
  description = "Real-time and historical energy consumption data from smart meters"
  
  time_partitioning {
    type                     = "DAY"
    field                   = "timestamp"
    require_partition_filter = false
  }
  
  clustering = ["meter_id", "building_type"]
  
  schema = jsonencode([
    {
      name = "meter_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the energy meter"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the measurement was taken"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "NULLABLE"
      description = "Geographic location of the meter (WKT format)"
    },
    {
      name = "energy_usage_kwh"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Energy usage in kilowatt-hours"
    },
    {
      name = "peak_demand"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Peak demand in kilowatts"
    },
    {
      name = "building_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Type of building (residential, commercial, industrial)"
    },
    {
      name = "occupancy_rate"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Building occupancy rate (0.0 to 1.0)"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Timestamp when the data was processed"
    }
  ])
  
  labels = merge(local.common_labels, {
    data-type = "energy-consumption"
  })
}

# Materialized view for real-time city dashboard
resource "google_bigquery_table" "real_time_city_dashboard" {
  depends_on = [
    google_bigquery_table.traffic_sensors,
    google_bigquery_table.air_quality_sensors,
    google_bigquery_table.energy_consumption
  ]
  
  dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  table_id   = "real_time_city_dashboard"
  
  description = "Materialized view for real-time smart city dashboard metrics"
  
  materialized_view {
    query = <<-SQL
      SELECT 
        TIMESTAMP_TRUNC(timestamp, HOUR) as hour,
        AVG(CASE WHEN vehicle_count IS NOT NULL THEN vehicle_count END) as avg_traffic_volume,
        AVG(CASE WHEN avg_speed IS NOT NULL THEN avg_speed END) as avg_vehicle_speed,
        COUNT(DISTINCT CASE WHEN congestion_level = 'heavy' THEN sensor_id END) as heavy_congestion_zones,
        AVG(CASE WHEN air_quality_index IS NOT NULL THEN air_quality_index END) as avg_air_quality,
        SUM(CASE WHEN energy_usage_kwh IS NOT NULL THEN energy_usage_kwh END) as total_energy_consumption,
        COUNT(DISTINCT sensor_id) as active_sensors
      FROM (
        SELECT sensor_id, timestamp, vehicle_count, avg_speed, congestion_level, 
               CAST(NULL AS INTEGER) as air_quality_index, CAST(NULL AS FLOAT64) as energy_usage_kwh
        FROM `${var.project_id}.${var.bigquery_dataset_id}.traffic_sensors`
        UNION ALL
        SELECT sensor_id, timestamp, CAST(NULL AS INTEGER), CAST(NULL AS FLOAT64), 
               CAST(NULL AS STRING), air_quality_index, CAST(NULL AS FLOAT64)
        FROM `${var.project_id}.${var.bigquery_dataset_id}.air_quality_sensors`
        UNION ALL
        SELECT meter_id as sensor_id, timestamp, CAST(NULL AS INTEGER), CAST(NULL AS FLOAT64), 
               CAST(NULL AS STRING), CAST(NULL AS INTEGER), energy_usage_kwh
        FROM `${var.project_id}.${var.bigquery_dataset_id}.energy_consumption`
      )
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
      GROUP BY hour
      ORDER BY hour DESC
    SQL
    
    enable_refresh = true
    refresh_interval_ms = 300000 # 5 minutes
  }
  
  labels = merge(local.common_labels, {
    purpose = "dashboard-materialized-view"
  })
}

# Data quality monitoring view
resource "google_bigquery_table" "data_quality_metrics" {
  depends_on = [
    google_bigquery_table.traffic_sensors,
    google_bigquery_table.air_quality_sensors,
    google_bigquery_table.energy_consumption
  ]
  
  dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  table_id   = "data_quality_metrics"
  
  description = "Data quality metrics for monitoring sensor data completeness and accuracy"
  
  view {
    query = <<-SQL
      SELECT
        'traffic_sensors' as table_name,
        COUNT(*) as total_records,
        COUNTIF(sensor_id IS NULL) as missing_sensor_ids,
        COUNTIF(vehicle_count IS NULL) as missing_vehicle_counts,
        COUNTIF(timestamp IS NULL) as missing_timestamps,
        COUNTIF(vehicle_count < 0) as invalid_vehicle_counts,
        COUNTIF(avg_speed < 0 OR avg_speed > 200) as invalid_speeds,
        CURRENT_TIMESTAMP() as last_updated
      FROM `${var.project_id}.${var.bigquery_dataset_id}.traffic_sensors`
      WHERE DATE(timestamp) = CURRENT_DATE()
      
      UNION ALL
      
      SELECT
        'air_quality_sensors' as table_name,
        COUNT(*) as total_records,
        COUNTIF(sensor_id IS NULL) as missing_sensor_ids,
        COUNTIF(air_quality_index IS NULL) as missing_aqi_values,
        COUNTIF(timestamp IS NULL) as missing_timestamps,
        COUNTIF(air_quality_index < 0 OR air_quality_index > 500) as invalid_aqi_values,
        COUNTIF(pm25 < 0 OR pm10 < 0) as invalid_pm_values,
        CURRENT_TIMESTAMP() as last_updated
      FROM `${var.project_id}.${var.bigquery_dataset_id}.air_quality_sensors`
      WHERE DATE(timestamp) = CURRENT_DATE()
      
      UNION ALL
      
      SELECT
        'energy_consumption' as table_name,
        COUNT(*) as total_records,
        COUNTIF(meter_id IS NULL) as missing_meter_ids,
        COUNTIF(energy_usage_kwh IS NULL) as missing_energy_values,
        COUNTIF(timestamp IS NULL) as missing_timestamps,
        COUNTIF(energy_usage_kwh < 0) as invalid_energy_values,
        COUNTIF(occupancy_rate < 0 OR occupancy_rate > 1) as invalid_occupancy_rates,
        CURRENT_TIMESTAMP() as last_updated
      FROM `${var.project_id}.${var.bigquery_dataset_id}.energy_consumption`
      WHERE DATE(timestamp) = CURRENT_DATE()
    SQL
    
    use_legacy_sql = false
  }
  
  labels = merge(local.common_labels, {
    purpose = "data-quality-monitoring"
  })
}

#------------------------------------------------------------------------------
# SERVICE ACCOUNTS - IAM and Security
#------------------------------------------------------------------------------

# Service account for Cloud Dataprep operations
resource "google_service_account" "dataprep_service_account" {
  depends_on = [time_sleep.api_enablement_delay]
  
  account_id   = var.dataprep_service_account_id
  display_name = "Cloud Dataprep Service Account"
  description  = "Service account for Cloud Dataprep data preparation and transformation operations"
}

# Service account for Dataflow pipeline operations  
resource "google_service_account" "dataflow_service_account" {
  depends_on = [time_sleep.api_enablement_delay]
  
  account_id   = var.dataflow_service_account_id
  display_name = "Dataflow Pipeline Service Account"
  description  = "Service account for Dataflow stream and batch processing pipelines"
}

# IAM role bindings for Dataprep service account
resource "google_project_iam_member" "dataprep_permissions" {
  for_each = toset([
    "roles/storage.admin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/dataflow.admin",
    "roles/pubsub.editor"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataprep_service_account.email}"
}

# IAM role bindings for Dataflow service account
resource "google_project_iam_member" "dataflow_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/pubsub.subscriber",
    "roles/pubsub.viewer",
    "roles/dataflow.worker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataflow_service_account.email}"
}

#------------------------------------------------------------------------------
# MONITORING AND ALERTING
#------------------------------------------------------------------------------

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  depends_on = [time_sleep.api_enablement_delay]
  
  display_name = "Smart City Analytics Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  description = "Email notifications for smart city analytics platform alerts"
}

# Alerting policy for low data ingestion rate
resource "google_monitoring_alert_policy" "low_data_ingestion" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [google_pubsub_topic.sensor_topics]
  
  display_name = "Low Data Ingestion Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Pub/Sub message rate below threshold"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_topic\" AND metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Alerting policy for data quality issues
resource "google_monitoring_alert_policy" "data_quality_issues" {
  count = var.enable_data_quality_monitoring ? 1 : 0
  
  depends_on = [google_bigquery_table.data_quality_metrics]
  
  display_name = "Data Quality Issues Detected"
  combiner     = "OR"
  
  conditions {
    display_name = "High rate of missing data"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/data_quality_errors\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 50
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
}

#------------------------------------------------------------------------------
# SCHEDULED QUERIES AND AUTOMATION
#------------------------------------------------------------------------------

# Scheduled query for daily city metrics aggregation
resource "google_bigquery_data_transfer_config" "daily_metrics_transfer" {
  depends_on = [google_bigquery_table.energy_consumption]
  
  display_name   = "Daily City Metrics Aggregation"
  data_source_id = "scheduled_query"
  location       = var.bigquery_location
  
  schedule = "0 6 * * *" # Daily at 6 AM
  
  destination_dataset_id = google_bigquery_dataset.smart_city_analytics.dataset_id
  
  params = {
    query = <<-SQL
      INSERT INTO `${var.project_id}.${var.bigquery_dataset_id}.hourly_city_metrics`
      SELECT 
        TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR) as hour,
        COALESCE(AVG(t.vehicle_count), 0) as avg_traffic_flow,
        COALESCE(AVG(a.air_quality_index), 0) as avg_air_quality,
        COALESCE(SUM(e.energy_usage_kwh), 0) as total_energy_consumption,
        "city_center" as city_zone
      FROM `${var.project_id}.${var.bigquery_dataset_id}.traffic_sensors` t
      FULL OUTER JOIN `${var.project_id}.${var.bigquery_dataset_id}.air_quality_sensors` a
        ON TIMESTAMP_TRUNC(t.timestamp, HOUR) = TIMESTAMP_TRUNC(a.timestamp, HOUR)
      FULL OUTER JOIN `${var.project_id}.${var.bigquery_dataset_id}.energy_consumption` e
        ON TIMESTAMP_TRUNC(COALESCE(t.timestamp, a.timestamp), HOUR) = TIMESTAMP_TRUNC(e.timestamp, HOUR)
      WHERE COALESCE(t.timestamp, a.timestamp, e.timestamp) >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
        AND COALESCE(t.timestamp, a.timestamp, e.timestamp) < TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR)
    SQL
  }
}

#------------------------------------------------------------------------------
# SAMPLE DATA GENERATION (for testing)
#------------------------------------------------------------------------------

# Sample traffic sensor data for testing Dataprep flows
resource "google_storage_bucket_object" "sample_traffic_data" {
  name   = "raw-data/traffic/sample_traffic_data.csv"
  bucket = google_storage_bucket.data_lake.name
  content = <<-CSV
sensor_id,timestamp,location,vehicle_count,avg_speed,congestion_level,weather_conditions
TRF001,2025-07-12T08:00:00Z,"POINT(-74.006 40.7128)",150,25.5,moderate,clear
TRF002,2025-07-12T08:00:00Z,"POINT(-74.007 40.7129)",200,15.2,heavy,rain
TRF003,2025-07-12T08:00:00Z,"POINT(-74.008 40.7130)",,35.8,light,
TRF001,2025-07-12T08:15:00Z,"POINT(-74.006 40.7128)",145,28.1,moderate,clear
TRF002,2025-07-12T08:15:00Z,"POINT(-74.007 40.7129)",180,18.5,heavy,rain
TRF003,2025-07-12T08:15:00Z,"POINT(-74.008 40.7130)",75,42.3,light,clear
CSV
}

# Sample air quality data for testing
resource "google_storage_bucket_object" "sample_air_quality_data" {
  name   = "raw-data/air-quality/sample_air_quality_data.csv"
  bucket = google_storage_bucket.data_lake.name
  content = <<-CSV
sensor_id,timestamp,location,pm25,pm10,ozone,no2,air_quality_index
AQ001,2025-07-12T08:00:00Z,"POINT(-74.006 40.7128)",12.5,18.3,0.08,25.4,45
AQ002,2025-07-12T08:00:00Z,"POINT(-74.007 40.7129)",15.2,,0.09,28.1,52
AQ003,2025-07-12T08:00:00Z,"POINT(-74.008 40.7130)",8.9,14.2,null,22.8,38
AQ001,2025-07-12T08:15:00Z,"POINT(-74.006 40.7128)",11.8,17.6,0.075,24.1,42
AQ002,2025-07-12T08:15:00Z,"POINT(-74.007 40.7129)",14.5,19.8,0.085,27.3,49
AQ003,2025-07-12T08:15:00Z,"POINT(-74.008 40.7130)",9.2,15.1,0.065,23.5,41
CSV
}

# Sample energy consumption data for testing
resource "google_storage_bucket_object" "sample_energy_data" {
  name   = "raw-data/energy/sample_energy_data.csv"
  bucket = google_storage_bucket.data_lake.name
  content = <<-CSV
meter_id,timestamp,location,energy_usage_kwh,peak_demand,building_type,occupancy_rate
EN001,2025-07-12T08:00:00Z,"POINT(-74.006 40.7128)",15.2,8.5,commercial,0.75
EN002,2025-07-12T08:00:00Z,"POINT(-74.007 40.7129)",8.9,5.2,residential,0.85
EN003,2025-07-12T08:00:00Z,"POINT(-74.008 40.7130)",25.6,12.8,industrial,0.60
EN001,2025-07-12T08:15:00Z,"POINT(-74.006 40.7128)",16.1,9.2,commercial,0.78
EN002,2025-07-12T08:15:00Z,"POINT(-74.007 40.7129)",9.5,5.8,residential,0.88
EN003,2025-07-12T08:15:00Z,"POINT(-74.008 40.7130)",24.8,11.9,industrial,0.58
CSV
}