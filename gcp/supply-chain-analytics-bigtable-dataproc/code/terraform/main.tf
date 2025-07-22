# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix        = random_id.suffix.hex
  bigtable_instance_id   = "${var.name_prefix}-bt-${local.resource_suffix}"
  dataproc_cluster_name  = "${var.name_prefix}-cluster-${local.resource_suffix}"
  bucket_name           = "${var.name_prefix}-data-${local.resource_suffix}"
  topic_name            = "sensor-data-topic-${local.resource_suffix}"
  function_name         = "process-sensor-data-${local.resource_suffix}"
  scheduler_job_name    = "supply-chain-analytics-job-${local.resource_suffix}"
  service_account_email = var.create_service_account ? google_service_account.analytics_sa[0].email : null
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "supply-chain-analytics"
  })
  
  # Required APIs for the solution
  required_apis = [
    "bigtable.googleapis.com",
    "dataproc.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create dedicated service account for analytics workload
resource "google_service_account" "analytics_sa" {
  count = var.create_service_account ? 1 : 0
  
  account_id   = var.service_account_name
  display_name = "Supply Chain Analytics Service Account"
  description  = "Service account for supply chain analytics workload"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "analytics_sa_roles" {
  for_each = var.create_service_account ? toset([
    "roles/bigtable.user",
    "roles/dataproc.worker",
    "roles/pubsub.subscriber",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.analytics_sa[0].email}"
  
  depends_on = [google_service_account.analytics_sa]
}

# Cloud Storage bucket for data processing and analytics
resource "google_storage_bucket" "analytics_bucket" {
  name          = local.bucket_name
  location      = var.storage_bucket_location
  project       = var.project_id
  storage_class = var.storage_bucket_class
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket objects for Spark jobs
resource "google_storage_bucket_object" "spark_job" {
  name   = "jobs/supply_chain_analytics.py"
  bucket = google_storage_bucket.analytics_bucket.name
  source = "${path.module}/spark_jobs/supply_chain_analytics.py"
  
  # Create the source file if it doesn't exist
  content = file("${path.module}/spark_jobs/supply_chain_analytics.py") != null ? file("${path.module}/spark_jobs/supply_chain_analytics.py") : templatefile("${path.module}/templates/supply_chain_analytics.py.tpl", {
    project_id = var.project_id
    bucket_name = local.bucket_name
  })
}

# Pub/Sub topic for sensor data ingestion
resource "google_pubsub_topic" "sensor_data" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Bigtable instance for real-time data storage
resource "google_bigtable_instance" "supply_chain" {
  name          = local.bigtable_instance_id
  display_name  = var.bigtable_display_name
  project       = var.project_id
  instance_type = var.bigtable_instance_type
  
  cluster {
    cluster_id   = "supply-chain-cluster"
    zone         = var.zone
    num_nodes    = var.bigtable_cluster_num_nodes
    storage_type = var.bigtable_storage_type
  }
  
  labels = local.common_labels
  
  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Bigtable table for sensor data
resource "google_bigtable_table" "sensor_data" {
  name          = "sensor_data"
  instance_name = google_bigtable_instance.supply_chain.name
  project       = var.project_id
  
  # Column families for organized data storage
  column_family {
    family = "sensor_readings"
  }
  
  column_family {
    family = "device_metadata"
  }
  
  column_family {
    family = "location_data"
  }
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source {
    content = templatefile("${path.module}/templates/cloud_function_main.py.tpl", {
      bigtable_instance_id = local.bigtable_instance_id
      project_id          = var.project_id
    })
    filename = "main.py"
  }
  source {
    content  = "google-cloud-bigtable==2.21.0\ngoogle-cloud-pubsub==2.18.4"
    filename = "requirements.txt"
  }
}

# Cloud Storage object for function source
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/function_source.zip"
  bucket = google_storage_bucket.analytics_bucket.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for real-time data processing
resource "google_cloudfunctions_function" "sensor_processor" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  runtime     = var.cloud_function_runtime
  description = "Process sensor data from Pub/Sub and store in Bigtable"
  
  available_memory_mb = var.cloud_function_memory
  timeout             = var.cloud_function_timeout
  entry_point        = "process_sensor_data"
  
  source_archive_bucket = google_storage_bucket.analytics_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.sensor_data.name
  }
  
  environment_variables = {
    BIGTABLE_INSTANCE_ID = local.bigtable_instance_id
    PROJECT_ID          = var.project_id
  }
  
  service_account_email = local.service_account_email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_bigtable_instance.supply_chain,
    google_bigtable_table.sensor_data
  ]
}

# Dataproc cluster for batch analytics
resource "google_dataproc_cluster" "analytics_cluster" {
  name    = local.dataproc_cluster_name
  project = var.project_id
  region  = var.region
  
  cluster_config {
    staging_bucket = google_storage_bucket.analytics_bucket.name
    
    master_config {
      num_instances    = 1
      machine_type     = var.dataproc_master_machine_type
      min_cpu_platform = "Intel Skylake"
      
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = var.dataproc_master_disk_size
      }
    }
    
    worker_config {
      num_instances    = var.dataproc_num_workers
      machine_type     = var.dataproc_worker_machine_type
      min_cpu_platform = "Intel Skylake"
      
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = var.dataproc_worker_disk_size
      }
    }
    
    preemptible_worker_config {
      num_instances = var.dataproc_num_preemptible_workers
      
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = var.dataproc_worker_disk_size
      }
    }
    
    software_config {
      image_version = var.dataproc_image_version
      
      optional_components = [
        "JUPYTER"
      ]
      
      properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
    }
    
    gce_cluster_config {
      zone = var.zone
      
      dynamic "service_account_scopes" {
        for_each = var.create_service_account ? [1] : []
        content {
          scopes = [
            "https://www.googleapis.com/auth/cloud-platform"
          ]
        }
      }
      
      service_account = local.service_account_email
      
      internal_ip_only = var.enable_private_nodes
      
      dynamic "shielded_instance_config" {
        for_each = var.bigtable_instance_type == "PRODUCTION" ? [1] : []
        content {
          enable_secure_boot          = true
          enable_vtpm                 = true
          enable_integrity_monitoring = true
        }
      }
    }
    
    # Autoscaling configuration
    autoscaling_config {
      max_instances = var.dataproc_max_workers
    }
    
    # Lifecycle configuration for cost optimization
    lifecycle_config {
      idle_delete_ttl = "600s"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.analytics_bucket
  ]
}

# Cloud Scheduler job for automated analytics
resource "google_cloud_scheduler_job" "analytics_job" {
  name      = local.scheduler_job_name
  project   = var.project_id
  region    = var.region
  schedule  = var.scheduler_cron_schedule
  time_zone = var.scheduler_timezone
  
  description = "Automated supply chain analytics job"
  
  http_target {
    uri         = "https://dataproc.googleapis.com/v1/projects/${var.project_id}/regions/${var.region}/jobs:submit"
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      job = {
        placement = {
          clusterName = local.dataproc_cluster_name
        }
        pysparkJob = {
          mainPythonFileUri = "gs://${local.bucket_name}/jobs/supply_chain_analytics.py"
          args = [
            var.project_id,
            local.bigtable_instance_id
          ]
        }
      }
    }))
    
    oauth_token {
      service_account_email = local.service_account_email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_dataproc_cluster.analytics_cluster,
    google_storage_bucket_object.spark_job
  ]
}

# Cloud Monitoring alert policy for low inventory
resource "google_monitoring_alert_policy" "low_inventory_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Low Inventory Alert - Supply Chain"
  project      = var.project_id
  
  conditions {
    display_name = "Inventory Level Check"
    
    condition_threshold {
      filter         = "resource.type=\"bigtable_table\""
      duration       = "300s"
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  documentation {
    content   = "Alert when inventory levels are critically low in the supply chain system"
    mime_type = "text/markdown"
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring dashboard for supply chain analytics
resource "google_monitoring_dashboard" "supply_chain_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Supply Chain Analytics Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Bigtable Operations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigtable_table\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.table_id"]
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Dataproc Job Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"dataproc_cluster\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}