# Hybrid Classical-Quantum AI Workflows Infrastructure
# This Terraform configuration deploys the complete infrastructure for
# quantum-enhanced portfolio optimization using Cirq and Vertex AI

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Common resource naming
  resource_prefix = "${var.prefix}-${local.suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    recipe = "hybrid-classical-quantum-ai-workflows"
    suffix = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "notebooks.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

# VPC Network for quantum computing workloads
resource "google_compute_network" "quantum_vpc" {
  name                    = "${local.resource_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  description            = "VPC network for hybrid quantum-classical AI workflows"

  depends_on = [time_sleep.wait_for_apis]
}

# Subnet for quantum computing resources
resource "google_compute_subnetwork" "quantum_subnet" {
  name          = "${local.resource_prefix}-subnet"
  network       = google_compute_network.quantum_vpc.id
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  description   = "Subnet for quantum computing and AI workloads"

  # Enable Private Google Access for accessing Google APIs without external IPs
  private_ip_google_access = var.enable_private_google_access

  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rules for quantum computing workloads
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.resource_prefix}-allow-internal"
  network = google_compute_network.quantum_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  description   = "Allow internal communication within the quantum VPC"
}

# Firewall rule for SSH access to Vertex AI Workbench
resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.resource_prefix}-allow-ssh"
  network = google_compute_network.quantum_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP range
  target_tags   = ["vertex-ai-workbench"]
  description   = "Allow SSH access to Vertex AI Workbench instances via IAP"
}

# Cloud Storage bucket for quantum computing data and results
resource "google_storage_bucket" "quantum_data" {
  name          = "${local.resource_prefix}-data"
  location      = var.region
  storage_class = var.storage_class
  force_destroy = true

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  # Versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management
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

  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels
}

# Cloud Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.resource_prefix}-functions"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = local.common_labels
}

# Service account for Vertex AI Workbench
resource "google_service_account" "vertex_ai_sa" {
  account_id   = "${local.resource_prefix}-vertex-ai"
  display_name = "Vertex AI Service Account for Quantum Computing"
  description  = "Service account for Vertex AI Workbench quantum computing instance"
}

# IAM bindings for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/storage.admin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/notebooks.runner"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
}

# Custom IAM role for quantum computing access
resource "google_project_iam_custom_role" "quantum_access" {
  role_id     = "${replace(local.resource_prefix, "-", "_")}_quantum_access"
  title       = "Quantum Computing Access"
  description = "Custom role for accessing quantum computing services"

  permissions = [
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.start",
    "compute.instances.stop",
    "cloudfunctions.functions.invoke",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update"
  ]
}

# Bind custom quantum role to Vertex AI service account
resource "google_project_iam_member" "vertex_ai_quantum_access" {
  project = var.project_id
  role    = google_project_iam_custom_role.quantum_access.id
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
}

# Vertex AI Workbench instance for quantum development
resource "google_notebooks_instance" "quantum_workbench" {
  name         = "${local.resource_prefix}-workbench"
  location     = var.zone
  machine_type = var.notebook_machine_type

  vm_image {
    project      = "deeplearning-platform-release"
    image_family = "tf-2-11-cu113-notebooks"
  }

  disk_size_gb = var.notebook_disk_size
  disk_type    = var.notebook_disk_type

  # Network configuration
  network = google_compute_network.quantum_vpc.id
  subnet  = google_compute_subnetwork.quantum_subnet.id

  # Disable external IP for security
  no_public_ip = true

  # Service account configuration
  service_account = google_service_account.vertex_ai_sa.email

  # Boot disk configuration
  boot_disk_size_gb = 100
  boot_disk_type    = "PD_STANDARD"

  # Instance metadata for quantum libraries installation
  metadata = {
    install-monitoring-agent = "true"
    enable-osconfig          = "true"
    startup-script = templatefile("${path.module}/startup-script.sh", {
      bucket_name = google_storage_bucket.quantum_data.name
      project_id  = var.project_id
    })
  }

  # Labels
  labels = local.common_labels

  # Tags for firewall rules
  tags = ["vertex-ai-workbench"]

  depends_on = [
    google_project_iam_member.vertex_ai_permissions,
    google_compute_subnetwork.quantum_subnet
  ]
}

# Create startup script for Vertex AI Workbench
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    bucket_name = google_storage_bucket.quantum_data.name
    project_id  = var.project_id
  })
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${local.resource_prefix}-functions"
  display_name = "Cloud Functions Service Account for Quantum Orchestration"
  description  = "Service account for Cloud Functions quantum workflow orchestration"
}

# IAM bindings for Cloud Functions service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.admin",
    "roles/aiplatform.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudfunctions.invoker"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Archive source code for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-main.py.tpl", {
      project_id  = var.project_id
      bucket_name = google_storage_bucket.quantum_data.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "quantum-orchestrator-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for hybrid workflow orchestration
resource "google_cloudfunctions_function" "quantum_orchestrator" {
  name        = "${local.resource_prefix}-orchestrator"
  description = "Hybrid quantum-classical portfolio optimization orchestrator"
  runtime     = var.function_runtime

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "orchestrate_hybrid_workflow"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    http_trigger {
      url = null
    }
  }

  # Environment variables
  environment_variables = {
    PROJECT_ID            = var.project_id
    BUCKET_NAME          = google_storage_bucket.quantum_data.name
    DEFAULT_PORTFOLIO_SIZE = var.default_portfolio_size
    DEFAULT_RISK_AVERSION = var.default_risk_aversion
    QUANTUM_PROCESSOR_ID = var.quantum_processor_id
    ENABLE_QUANTUM_PROCESSOR = var.enable_quantum_processor
  }

  # Service account
  service_account_email = google_service_account.function_sa.email

  # Labels
  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_permissions
  ]
}

# Cloud Function IAM member for public access
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.quantum_orchestrator.project
  region         = google_cloudfunctions_function.quantum_orchestrator.region
  cloud_function = google_cloudfunctions_function.quantum_orchestrator.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Cloud Scheduler job for periodic portfolio optimization
resource "google_cloud_scheduler_job" "quantum_optimization" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${local.resource_prefix}-optimization"
  description = "Periodic quantum portfolio optimization"
  schedule    = "0 9 * * 1-5" # 9 AM on weekdays
  time_zone   = "America/New_York"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.quantum_orchestrator.https_trigger_url
    
    body = base64encode(jsonencode({
      portfolio_data = {
        n_assets      = var.default_portfolio_size
        risk_aversion = var.default_risk_aversion
        trigger_type  = "scheduled"
      }
    }))

    headers = {
      "Content-Type" = "application/json"
    }
  }

  depends_on = [google_cloudfunctions_function.quantum_orchestrator]
}

# Cloud Monitoring notification channel
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Quantum Portfolio Optimization Alerts"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com" # Replace with actual email
  }
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Quantum Orchestrator Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.quantum_orchestrator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.enable_monitoring ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }
}

# BigQuery dataset for quantum optimization results
resource "google_bigquery_dataset" "quantum_results" {
  dataset_id  = "${replace(local.resource_prefix, "-", "_")}_results"
  description = "Dataset for storing quantum optimization results and analytics"
  location    = var.region

  # Access control
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role           = "READER"
    service_account_email = google_service_account.vertex_ai_sa.email
  }

  access {
    role           = "WRITER"
    service_account_email = google_service_account.function_sa.email
  }

  labels = local.common_labels
}

# BigQuery table for optimization results
resource "google_bigquery_table" "optimization_results" {
  dataset_id = google_bigquery_dataset.quantum_results.dataset_id
  table_id   = "optimization_results"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "portfolio_weights"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "optimization_cost"
      type = "FLOAT"
      mode = "REQUIRED"
    },
    {
      name = "quantum_parameters"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "classical_metrics"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "hybrid_score"
      type = "FLOAT"
      mode = "NULLABLE"
    }
  ])

  labels = local.common_labels
}

# Cloud Logging sink for function logs
resource "google_logging_project_sink" "quantum_logs" {
  name        = "${local.resource_prefix}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.quantum_data.name}/logs"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.quantum_orchestrator.name}\""

  unique_writer_identity = true
}

# Grant storage write access to logging sink
resource "google_storage_bucket_iam_member" "logs_writer" {
  bucket = google_storage_bucket.quantum_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.quantum_logs.writer_identity
}

# Cloud Monitoring dashboard for quantum optimization
resource "google_monitoring_dashboard" "quantum_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Hybrid Quantum-Classical Portfolio Optimization"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Invocations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.quantum_orchestrator.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}