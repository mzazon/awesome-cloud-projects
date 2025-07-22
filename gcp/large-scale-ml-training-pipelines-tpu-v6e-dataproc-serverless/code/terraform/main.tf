# Generate random suffixes for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "tpu.googleapis.com",
    "dataproc.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create a service account for TPU and Dataproc operations
resource "google_service_account" "ml_pipeline_sa" {
  account_id   = "ml-pipeline-sa-${random_id.suffix.hex}"
  display_name = "ML Pipeline Service Account"
  description  = "Service account for TPU v6e and Dataproc Serverless operations"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Assign necessary IAM roles to the service account
resource "google_project_iam_member" "ml_pipeline_roles" {
  for_each = toset([
    "roles/tpu.admin",
    "roles/dataproc.editor",
    "roles/storage.admin",
    "roles/aiplatform.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/compute.instanceAdmin.v1"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ml_pipeline_sa.email}"

  depends_on = [google_service_account.ml_pipeline_sa]
}

# Create Cloud Storage bucket for the ML training pipeline
resource "google_storage_bucket" "ml_training_bucket" {
  name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for enhanced security
  uniform_bucket_level_access = var.bucket_uniform_access
  
  # Configure object versioning for data protection
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Enable CORS for TPU and Dataproc access
  cors {
    origin          = ["*"]
    method          = ["GET", "POST", "PUT"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  # Apply resource labels
  labels = var.resource_labels

  # Force deletion protection (configurable)
  force_destroy = var.auto_delete_bucket

  depends_on = [google_project_service.required_apis]
}

# Create bucket objects for directory structure
resource "google_storage_bucket_object" "pipeline_directories" {
  for_each = toset([
    "raw-data/",
    "processed-data/",
    "models/",
    "checkpoints/",
    "logs/",
    "scripts/"
  ])

  name   = each.value
  bucket = google_storage_bucket.ml_training_bucket.name
  content = " "  # Empty content for directory markers
}

# Upload sample training script to Cloud Storage
resource "google_storage_bucket_object" "preprocessing_script" {
  name   = "scripts/preprocessing_job.py"
  bucket = google_storage_bucket.ml_training_bucket.name
  content = templatefile("${path.module}/scripts/preprocessing_job.py.tpl", {
    bucket_name = google_storage_bucket.ml_training_bucket.name
  })
}

# Upload TPU training script to Cloud Storage
resource "google_storage_bucket_object" "tpu_training_script" {
  name   = "scripts/tpu_training_script.py"
  bucket = google_storage_bucket.ml_training_bucket.name
  content = templatefile("${path.module}/scripts/tpu_training_script.py.tpl", {
    bucket_name = google_storage_bucket.ml_training_bucket.name
    project_id  = var.project_id
  })
}

# Create firewall rule for TPU communication
resource "google_compute_firewall" "tpu_firewall" {
  name    = "allow-tpu-communication-${random_id.suffix.hex}"
  network = var.tpu_network
  project = var.project_id

  description = "Allow TPU communication for ML training pipeline"

  allow {
    protocol = "tcp"
    ports    = ["8470-8490", "22"]
  }

  allow {
    protocol = "udp"
    ports    = ["8470-8490"]
  }

  source_ranges = var.firewall_source_ranges
  target_tags   = ["ml-training"]

  depends_on = [google_project_service.required_apis]
}

# Create Cloud TPU v6e instance for training
resource "google_tpu_node" "training_tpu" {
  name               = "${var.tpu_name_prefix}-${random_id.suffix.hex}"
  zone               = var.zone
  project            = var.project_id
  accelerator_type   = var.tpu_accelerator_type
  tensorflow_version = var.tpu_runtime_version
  
  network    = var.tpu_network
  subnetwork = var.tpu_subnetwork

  # Configure TPU for optimal performance
  scheduling_config {
    preemptible = var.enable_preemptible_tpu
  }

  # Apply resource labels
  labels = merge(var.resource_labels, {
    component = "tpu-training"
    accelerator = replace(var.tpu_accelerator_type, "-", "_")
  })

  # Use custom service account if provided
  service_account = var.custom_service_account_email != "" ? var.custom_service_account_email : google_service_account.ml_pipeline_sa.email

  depends_on = [
    google_project_service.required_apis,
    google_service_account.ml_pipeline_sa,
    google_project_iam_member.ml_pipeline_roles,
    google_compute_firewall.tpu_firewall
  ]

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

# Create Dataproc Serverless batch job for preprocessing
resource "google_dataproc_batch" "preprocessing_batch" {
  batch_id = "${var.dataproc_batch_id_prefix}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  pyspark_batch {
    main_python_file_uri = "gs://${google_storage_bucket.ml_training_bucket.name}/scripts/preprocessing_job.py"
    
    args = [
      "gs://${google_storage_bucket.ml_training_bucket.name}/raw-data/",
      "gs://${google_storage_bucket.ml_training_bucket.name}/processed-data/"
    ]

    python_file_uris = []
    jar_file_uris    = []
    file_uris        = []
    archive_uris     = []
  }

  runtime_config {
    version = "2.1"
    
    properties = {
      "spark.executor.memory"              = var.dataproc_executor_memory
      "spark.driver.memory"                = var.dataproc_driver_memory
      "spark.executor.instances"           = "2"
      "spark.dynamicAllocation.enabled"    = "true"
      "spark.dynamicAllocation.maxExecutors" = tostring(var.dataproc_max_executors)
      "spark.sql.adaptive.enabled"         = "true"
      "spark.sql.adaptive.coalescePartitions.enabled" = "true"
    }
  }

  environment_config {
    execution_config {
      service_account = var.custom_service_account_email != "" ? var.custom_service_account_email : google_service_account.ml_pipeline_sa.email
      subnetwork_uri  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.tpu_subnetwork}"
      
      network_tags = ["ml-training"]
    }
  }

  # Apply resource labels
  labels = merge(var.resource_labels, {
    component = "dataproc-preprocessing"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.preprocessing_script,
    google_service_account.ml_pipeline_sa,
    google_project_iam_member.ml_pipeline_roles
  ]

  timeouts {
    create = "30m"
    delete = "10m"
  }
}

# Create Vertex AI custom training job configuration
resource "google_vertex_ai_custom_job" "tpu_training_job" {
  display_name = "${var.vertex_ai_training_display_name}-${random_id.suffix.hex}"
  location     = var.region
  project      = var.project_id

  job_spec {
    worker_pool_specs {
      machine_spec {
        machine_type     = "cloud-tpu"
        accelerator_type = "TPU_V6E"
        accelerator_count = 8
      }
      
      replica_count = 1
      
      container_spec {
        image_uri = var.vertex_ai_container_image
        command   = ["python"]
        args      = ["/tmp/training_script.py"]
        
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.ml_training_bucket.name
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "TPU_NAME"
          value = google_tpu_node.training_tpu.name
        }
      }
    }
    
    base_output_directory {
      output_uri_prefix = "gs://${google_storage_bucket.ml_training_bucket.name}/models/"
    }
    
    service_account = var.custom_service_account_email != "" ? var.custom_service_account_email : google_service_account.ml_pipeline_sa.email
    
    network = "projects/${var.project_id}/global/networks/${var.tpu_network}"
  }

  # Apply resource labels
  labels = merge(var.resource_labels, {
    component = "vertex-ai-training"
  })

  depends_on = [
    google_project_service.required_apis,
    google_tpu_node.training_tpu,
    google_storage_bucket_object.tpu_training_script,
    google_service_account.ml_pipeline_sa,
    google_project_iam_member.ml_pipeline_roles
  ]
}

# Create Cloud Monitoring dashboard for TPU training
resource "google_monitoring_dashboard" "tpu_training_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = var.monitoring_dashboard_name
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "TPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"tpu_worker\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.labels.node_name"]
                      }
                    }
                  }
                  plotType         = "LINE"
                  targetAxis       = "Y1"
                  legendTemplate   = "TPU ${resource.labels.node_name}"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Utilization %"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Dataproc Batch Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"dataproc_batch\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "STACKED_BAR"
                }
              ]
            }
          }
        }
      ]
    }
  })

  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for TPU training issues
resource "google_monitoring_alert_policy" "tpu_training_alerts" {
  count = var.enable_monitoring && length(var.alert_notification_channels) > 0 ? 1 : 0
  
  display_name = "TPU Training Alerts"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "High TPU Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"tpu_worker\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.alert_notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_project_service.required_apis]
}

# Create a Cloud Function for pipeline orchestration (optional)
resource "google_cloudfunctions2_function" "pipeline_orchestrator" {
  name     = "ml-pipeline-orchestrator-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python39"
    entry_point = "orchestrate_pipeline"
    
    source {
      storage_source {
        bucket = google_storage_bucket.ml_training_bucket.name
        object = "functions/orchestrator.zip"
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "256M"
    timeout_seconds    = 540
    
    environment_variables = {
      BUCKET_NAME        = google_storage_bucket.ml_training_bucket.name
      TPU_NAME          = google_tpu_node.training_tpu.name
      DATAPROC_BATCH_ID = google_dataproc_batch.preprocessing_batch.batch_id
      PROJECT_ID        = var.project_id
      REGION            = var.region
    }
    
    service_account_email = google_service_account.ml_pipeline_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.ml_pipeline_sa,
    google_project_iam_member.ml_pipeline_roles
  ]
}

# Create IAM binding for Cloud Function invocation
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.pipeline_orchestrator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.ml_pipeline_sa.email}"
}