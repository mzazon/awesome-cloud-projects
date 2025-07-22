# Local values for resource naming and configuration
locals {
  # Generate random suffix for unique resource names
  random_suffix = random_id.main.hex
  
  # Resource naming convention
  cluster_name_full = "${var.cluster_name}-${local.random_suffix}"
  bucket_name       = "${var.project_id}-weather-data-${local.random_suffix}"
  function_name     = "weather-processor-${local.random_suffix}"
  topic_name        = "weather-scaling-${local.random_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment = local.cluster_name_full
    created-by = "terraform"
  })
}

# Random ID for unique resource naming
resource "random_id" "main" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "cloudscheduler.googleapis.com",
    "file.googleapis.com",
    "containerregistry.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iap.googleapis.com"
  ])
  
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC network for HPC cluster
resource "google_compute_network" "hpc_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  mtu                     = 1500
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for HPC cluster
resource "google_compute_subnetwork" "hpc_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.hpc_network.id
  region        = var.region
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true
  
  # Secondary IP ranges for pods and services (if needed for future container workloads)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Firewall rules for HPC cluster communication
resource "google_compute_firewall" "hpc_internal" {
  name    = "${var.network_name}-internal"
  network = google_compute_network.hpc_network.name
  
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
  target_tags   = ["hpc-cluster"]
}

# Firewall rule for SSH access (with IAP if enabled)
resource "google_compute_firewall" "ssh_access" {
  name    = "${var.network_name}-ssh"
  network = google_compute_network.hpc_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  # Use IAP ranges if enabled, otherwise use authorized networks
  source_ranges = var.enable_iap ? ["35.235.240.0/20"] : var.authorized_networks
  target_tags   = ["hpc-cluster"]
}

# Cloud Storage bucket for weather data
resource "google_storage_bucket" "weather_data" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = !var.deletion_protection
  
  versioning {
    enabled = true
  }
  
  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# KMS keyring for encryption
resource "google_kms_key_ring" "weather_keyring" {
  name     = "weather-hpc-keyring-${local.random_suffix}"
  location = var.region
  
  depends_on = [google_project_service.required_apis]
}

# KMS key for storage encryption
resource "google_kms_crypto_key" "storage_key" {
  name     = "weather-storage-key"
  key_ring = google_kms_key_ring.weather_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  lifecycle {
    prevent_destroy = true
  }
}

# Secret Manager secret for Weather API key
resource "google_secret_manager_secret" "weather_api_key" {
  secret_id = "weather-api-key-${local.random_suffix}"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Secret version for Weather API key
resource "google_secret_manager_secret_version" "weather_api_key_version" {
  secret      = google_secret_manager_secret.weather_api_key.id
  secret_data = var.weather_api_key
}

# Pub/Sub topic for weather scaling events
resource "google_pubsub_topic" "weather_scaling" {
  name = local.topic_name
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for processing scaling events
resource "google_pubsub_subscription" "weather_scaling_sub" {
  name  = "${local.topic_name}-sub"
  topic = google_pubsub_topic.weather_scaling.name
  
  # Configure message retention and acknowledgement
  message_retention_duration = "604800s" # 7 days
  ack_deadline_seconds       = 300
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.weather_scaling_dlq.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Dead letter queue for failed scaling messages
resource "google_pubsub_topic" "weather_scaling_dlq" {
  name = "${local.topic_name}-dlq"
  
  labels = local.common_labels
}

# Filestore instance for shared cluster storage
resource "google_filestore_instance" "hpc_shared_storage" {
  name     = "hpc-shared-${local.random_suffix}"
  location = var.zone
  tier     = var.filestore_tier
  
  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "shared"
  }
  
  networks {
    network = google_compute_network.hpc_network.name
    modes   = ["MODE_IPV4"]
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Function source code archive
data "archive_file" "weather_function_source" {
  type        = "zip"
  output_path = "${path.module}/weather-function-source.zip"
  
  source {
    content = templatefile("${path.module}/weather_function.py.tpl", {
      project_id    = var.project_id
      topic_name    = local.topic_name
      bucket_name   = local.bucket_name
      locations     = var.weather_monitoring_locations
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-function-source"
  location      = var.region
  force_destroy = true
  
  labels = local.common_labels
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "weather_function_source" {
  name   = "weather-function-${local.random_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.weather_function_source.output_path
}

# IAM service account for Cloud Function
resource "google_service_account" "weather_function_sa" {
  account_id   = "weather-function-sa-${local.random_suffix}"
  display_name = "Weather Processing Function Service Account"
  description  = "Service account for weather data processing and scaling decisions"
}

# IAM bindings for function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/pubsub.publisher",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.weather_function_sa.email}"
}

# Cloud Function for weather processing
resource "google_cloudfunctions_function" "weather_processor" {
  name        = local.function_name
  description = "Process weather data and generate scaling decisions"
  runtime     = "python39"
  region      = var.region
  
  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  entry_point          = "weather_processor"
  service_account_email = google_service_account.weather_function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.weather_function_source.name
  
  # HTTP trigger for scheduler
  trigger {
    https_trigger {}
  }
  
  environment_variables = {
    GCP_PROJECT        = var.project_id
    PUBSUB_TOPIC       = local.topic_name
    STORAGE_BUCKET     = local.bucket_name
    WEATHER_API_SECRET = google_secret_manager_secret.weather_api_key.secret_id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.weather_function_source
  ]
}

# Cloud Scheduler jobs for automated weather monitoring
resource "google_cloud_scheduler_job" "weather_check" {
  name             = "weather-check-${local.random_suffix}"
  description      = "Regular weather data collection and scaling analysis"
  schedule         = var.weather_check_schedule
  time_zone        = "UTC"
  attempt_deadline = "300s"
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.weather_processor.https_trigger_url
    
    oidc_token {
      service_account_email = google_service_account.weather_function_sa.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Enhanced storm monitoring scheduler
resource "google_cloud_scheduler_job" "storm_monitor" {
  name             = "storm-monitor-${local.random_suffix}"
  description      = "Enhanced weather monitoring during severe weather events"
  schedule         = var.storm_monitor_schedule
  time_zone        = "UTC"
  attempt_deadline = "300s"
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.weather_processor.https_trigger_url
    
    oidc_token {
      service_account_email = google_service_account.weather_function_sa.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring notification channel for alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  display_name = "Weather HPC Email Alerts"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com" # Replace with actual email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alerting policy for high scaling factors
resource "google_monitoring_alert_policy" "high_scaling_factor" {
  display_name = "High Weather Scaling Factor Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High scaling factor detected"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/weather/scaling_factor\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1.5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.email_alerts.name
  ]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Custom monitoring dashboard for weather and cluster metrics
resource "google_monitoring_dashboard" "weather_hpc_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Weather-Aware HPC Scaling Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Weather Scaling Factor by Region"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/weather/scaling_factor\""
                      aggregation = {
                        alignmentPeriod      = "300s"
                        perSeriesAligner     = "ALIGN_MEAN"
                        crossSeriesReducer   = "REDUCE_MEAN"
                        groupByFields        = ["metric.label.region"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Scaling Factor"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Cluster CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
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

# Compute instance template for HPC cluster nodes
resource "google_compute_instance_template" "hpc_node_template" {
  name_prefix  = "hpc-node-${local.random_suffix}-"
  machine_type = var.cluster_machine_type
  
  disk {
    source_image = "projects/hpc-toolkit-slurm/global/images/family/hpc-toolkit-slurm"
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-ssd"
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.hpc_subnet.name
    
    # Only assign external IP if IAP is disabled
    dynamic "access_config" {
      for_each = var.enable_iap ? [] : [1]
      content {
        nat_ip = null
      }
    }
  }
  
  metadata = {
    enable-oslogin    = "TRUE"
    startup-script    = templatefile("${path.module}/startup_script.sh.tpl", {
      filestore_ip    = google_filestore_instance.hpc_shared_storage.networks[0].ip_addresses[0]
      filestore_share = google_filestore_instance.hpc_shared_storage.file_shares[0].name
    })
  }
  
  tags = ["hpc-cluster", "hpc-compute-node"]
  
  service_account {
    email = google_service_account.hpc_cluster_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # Use spot instances if enabled
  scheduling {
    preemptible       = var.enable_spot_instances
    on_host_maintenance = var.enable_spot_instances ? "TERMINATE" : "MIGRATE"
    automatic_restart = !var.enable_spot_instances
  }
  
  labels = local.common_labels
  
  lifecycle {
    create_before_destroy = true
  }
}

# Service account for HPC cluster nodes
resource "google_service_account" "hpc_cluster_sa" {
  account_id   = "hpc-cluster-sa-${local.random_suffix}"
  display_name = "HPC Cluster Service Account"
  description  = "Service account for HPC cluster compute nodes"
}

# IAM bindings for cluster service account
resource "google_project_iam_member" "cluster_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.subscriber",
    "roles/compute.instanceAdmin.v1"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.hpc_cluster_sa.email}"
}

# Managed instance group for auto-scaling HPC cluster
resource "google_compute_region_instance_group_manager" "hpc_cluster_igm" {
  name               = "hpc-cluster-igm-${local.random_suffix}"
  region             = var.region
  base_instance_name = "hpc-node"
  target_size        = var.cluster_min_nodes
  
  version {
    instance_template = google_compute_instance_template.hpc_node_template.id
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.hpc_health_check.id
    initial_delay_sec = 300
  }
  
  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 2
  }
  
  depends_on = [google_project_service.required_apis]
}

# Health check for HPC cluster nodes
resource "google_compute_health_check" "hpc_health_check" {
  name = "hpc-health-check-${local.random_suffix}"
  
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  tcp_health_check {
    port = "22"
  }
}

# Auto-scaler for weather-aware scaling
resource "google_compute_region_autoscaler" "hpc_cluster_autoscaler" {
  name   = "hpc-cluster-autoscaler-${local.random_suffix}"
  region = var.region
  target = google_compute_region_instance_group_manager.hpc_cluster_igm.id
  
  autoscaling_policy {
    max_replicas    = var.cluster_max_nodes
    min_replicas    = var.cluster_min_nodes
    cooldown_period = 300
    
    cpu_utilization {
      target = 0.7
    }
    
    # Custom metric for weather-based scaling
    metric {
      name   = "custom.googleapis.com/weather/scaling_factor"
      type   = "GAUGE"
      target = 1.0
    }
  }
}

# Budget for cost monitoring
resource "google_billing_budget" "weather_hpc_budget" {
  billing_account = data.google_billing_account.account.id
  display_name    = "Weather HPC Budget - ${local.cluster_name_full}"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/compute.googleapis.com",
      "services/cloudfunctions.googleapis.com",
      "services/file.googleapis.com"
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }
  
  all_updates_rule {
    monitoring_notification_channels = [
      google_monitoring_notification_channel.email_alerts.name
    ]
    disable_default_iam_recipients = true
  }
}

# Data source for billing account
data "google_billing_account" "account" {
  display_name = "My Billing Account"
  open         = true
}