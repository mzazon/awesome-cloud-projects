# AlloyDB AI Performance Automation Infrastructure
# This Terraform configuration deploys a complete intelligent database performance optimization system
# combining AlloyDB AI, Cloud Monitoring, Vertex AI, and automated optimization workflows

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Computed values for resource naming and configuration
  resource_suffix    = random_id.suffix.hex
  cluster_name      = var.alloydb_cluster_id != "" ? var.alloydb_cluster_id : "${var.resource_prefix}-cluster-${local.resource_suffix}"
  instance_name     = "${var.resource_prefix}-primary-${local.resource_suffix}"
  vpc_name          = "${var.resource_prefix}-vpc-${local.resource_suffix}"
  subnet_name       = "${var.resource_prefix}-subnet-${local.resource_suffix}"
  vertex_ai_region  = var.vertex_ai_region != "" ? var.vertex_ai_region : var.region
  
  # Combine default and custom labels
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    created-by  = "alloydb-ai-performance-automation"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "alloydb.googleapis.com",
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "servicenetworking.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create VPC network for AlloyDB with custom configuration
resource "google_compute_network" "alloydb_vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
  description            = "VPC network for AlloyDB AI performance automation cluster"

  depends_on = [google_project_service.required_apis]
}

# Create subnet with appropriate IP range for AlloyDB workloads
resource "google_compute_subnetwork" "alloydb_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.vpc_cidr_range
  region        = var.region
  network       = google_compute_network.alloydb_vpc.id
  description   = "Subnet for AlloyDB AI cluster and associated resources"

  # Enable private Google access for AI services
  private_ip_google_access = true

  # Secondary IP ranges for potential future expansion
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.2.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.3.0.0/16"
  }
}

# Allocate IP range for private service connection to AlloyDB
resource "google_compute_global_address" "private_service_range" {
  name          = "alloydb-range-${local.resource_suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.alloydb_vpc.id
  description   = "IP range for AlloyDB private service connection"

  depends_on = [google_project_service.required_apis]
}

# Create private service connection for AlloyDB
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.alloydb_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
  
  deletion_policy = "ABANDON"
}

# Create AlloyDB cluster with AI capabilities and optimal configuration
resource "google_alloydb_cluster" "main" {
  provider   = google-beta
  cluster_id = local.cluster_name
  location   = var.region
  network    = google_compute_network.alloydb_vpc.id

  # Initial user configuration for database access
  initial_user {
    user     = "postgres"
    password = random_password.db_password.result
  }

  # Enable automated backup with configurable retention
  dynamic "automated_backup_policy" {
    for_each = var.alloydb_backup_enabled ? [1] : []
    content {
      location = var.region
      backup_window = "02:00"
      enabled       = true

      # Weekly backup schedule for long-term retention
      weekly_schedule {
        days_of_week = ["MONDAY", "WEDNESDAY", "FRIDAY"]
        start_times {
          hours   = 2
          minutes = 0
        }
      }

      # Retention policy based on configuration
      quantity_based_retention {
        count = var.alloydb_backup_retention_days
      }
    }
  }

  # Database flags for optimal AI workload performance
  database_flags = {
    "cloudsql.iam_authentication"           = var.enable_iam_authentication ? "on" : "off"
    "shared_preload_libraries"              = "vector"
    "log_statement"                         = "all"
    "log_min_duration_statement"            = "1000"
    "track_activity_query_size"             = "4096"
    "pg_stat_statements.track"              = "all"
    "pg_stat_statements.max"                = "10000"
  }

  labels = local.common_labels

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

# Generate secure random password for database
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# Create primary AlloyDB instance with AI-optimized configuration
resource "google_alloydb_instance" "primary" {
  provider    = google-beta
  cluster     = google_alloydb_cluster.main.name
  instance_id = local.instance_name
  
  instance_type            = "PRIMARY"
  machine_config {
    cpu_count = var.alloydb_cpu_count
  }
  
  availability_type = var.alloydb_availability_type

  # Query insights configuration for performance monitoring
  query_insights_config {
    query_string_length     = 4096
    record_application_tags = true
    record_client_address   = true
  }

  # Read pool configuration for analytics workloads
  read_pool_config {
    node_count = 1
  }

  labels = local.common_labels

  depends_on = [google_alloydb_cluster.main]
}

# Store database connection details in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "alloydb-password-${local.resource_suffix}"

  replication {
    automatic = true
  }

  labels = local.common_labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Create Pub/Sub topic for performance events and optimization workflows
resource "google_pubsub_topic" "performance_events" {
  name = "alloydb-performance-events-${local.resource_suffix}"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source code and AI model artifacts
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-alloydb-functions-${local.resource_suffix}"
  location = var.region

  # Versioning for function source code management
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  labels                     = local.common_labels
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/alloydb-optimizer-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      cluster_name = local.cluster_name
      region       = var.region
    })
    filename = "main.py"
  }

  source {
    content = templatefile("${path.module}/function_code/requirements.txt", {})
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "alloydb-optimizer-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create Service Account for Cloud Functions with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = "alloydb-optimizer-${local.resource_suffix}"
  display_name = "AlloyDB Performance Optimizer Function Service Account"
  description  = "Service account for AlloyDB AI performance optimization functions"
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/alloydb.client",
    "roles/monitoring.viewer",
    "roles/aiplatform.user",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy Cloud Function for performance optimization
resource "google_cloudfunctions2_function" "performance_optimizer" {
  name     = "alloydb-performance-optimizer-${local.resource_suffix}"
  location = var.region

  build_config {
    runtime     = var.function_runtime
    entry_point = "optimize_alloydb_performance"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory_mb}Mi"
    timeout_seconds       = var.function_timeout_seconds
    service_account_email = google_service_account.function_sa.email

    environment_variables = {
      PROJECT_ID      = var.project_id
      CLUSTER_NAME    = local.cluster_name
      REGION          = var.region
      SECRET_NAME     = google_secret_manager_secret.db_password.secret_id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.performance_events.id
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_permissions
  ]
}

# Create Vertex AI dataset for performance metrics
resource "google_vertex_ai_dataset" "performance_dataset" {
  display_name          = "alloydb-performance-dataset-${local.resource_suffix}"
  metadata_schema_uri   = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region               = local.vertex_ai_region

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler jobs for automated performance monitoring
resource "google_cloud_scheduler_job" "performance_analyzer" {
  name             = "performance-analyzer-${local.resource_suffix}"
  region           = var.region
  schedule         = var.performance_analysis_schedule
  time_zone        = var.timezone
  description      = "Automated AlloyDB performance analysis and optimization"

  pubsub_target {
    topic_name = google_pubsub_topic.performance_events.id
    data       = base64encode(jsonencode({
      action  = "analyze_performance"
      cluster = local.cluster_name
    }))
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "daily_performance_report" {
  name             = "daily-performance-report-${local.resource_suffix}"
  region           = var.region
  schedule         = var.daily_report_schedule
  time_zone        = var.timezone
  description      = "Daily AlloyDB performance optimization report generation"

  pubsub_target {
    topic_name = google_pubsub_topic.performance_events.id
    data       = base64encode(jsonencode({
      action  = "generate_report"
      cluster = local.cluster_name
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for AlloyDB performance visualization
resource "google_monitoring_dashboard" "alloydb_performance" {
  count        = var.monitoring_enabled ? 1 : 0
  display_name = "AlloyDB AI Performance Dashboard - ${local.cluster_name}"

  dashboard_json = jsonencode({
    displayName = "AlloyDB AI Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Query Performance Score"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"alloydb_database\" AND resource.labels.cluster_id=\"${local.cluster_name}\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Performance Score"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "AI Optimization Actions"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.performance_optimizer.name}\""
                  aggregation = {
                    alignmentPeriod = "3600s"
                    perSeriesAligner = "ALIGN_SUM"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 4
          widget = {
            title = "Database Connection Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"alloydb_database\" AND metric.type=\"alloydb.googleapis.com/database/postgresql/num_backends\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                },
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"alloydb_database\" AND metric.type=\"alloydb.googleapis.com/database/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Connections / CPU %"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_alloydb_instance.primary]
}

# Create alerting policy for performance anomalies
resource "google_monitoring_alert_policy" "performance_anomaly" {
  count        = var.monitoring_enabled ? 1 : 0
  display_name = "AlloyDB Performance Anomaly Alert - ${local.cluster_name}"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High query latency detected"
    
    condition_threshold {
      filter          = "resource.type=\"alloydb_database\" AND resource.labels.cluster_id=\"${local.cluster_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.performance_threshold_latency_ms

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  conditions {
    display_name = "High CPU utilization"
    
    condition_threshold {
      filter          = "resource.type=\"alloydb_database\" AND metric.type=\"alloydb.googleapis.com/database/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.alert_notification_channels

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_alloydb_instance.primary]
}

# Create custom metric descriptor for AI-generated performance scores
resource "google_monitoring_metric_descriptor" "performance_score" {
  type         = "custom.googleapis.com/alloydb/query_performance_score"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "1"
  description  = "AI-generated performance score for AlloyDB queries"
  display_name = "AlloyDB Query Performance Score"

  labels {
    key         = "database_name"
    value_type  = "STRING"
    description = "Name of the database"
  }

  labels {
    key         = "query_type"
    value_type  = "STRING"
    description = "Type of query being executed"
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Create budget alert for cost monitoring
resource "google_billing_budget" "alloydb_cost_budget" {
  count           = var.enable_cost_alerts ? 1 : 0
  billing_account = data.google_billing_account.account.id
  display_name    = "AlloyDB Performance Automation Budget - ${local.cluster_name}"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/F25E-1F79-5C8C",  # AlloyDB
      "services/6F81-5844-456A",  # Vertex AI
      "services/FAD4-5175-0B22"   # Cloud Functions
    ]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.daily_cost_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis      = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }
}

# Data source for billing account
data "google_billing_account" "account" {
  count        = var.enable_cost_alerts ? 1 : 0
  display_name = "My Billing Account"
}