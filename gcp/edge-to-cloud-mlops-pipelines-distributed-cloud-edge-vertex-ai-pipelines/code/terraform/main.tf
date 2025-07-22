# =============================================================================
# Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI
# =============================================================================
# This Terraform configuration creates a comprehensive MLOps pipeline that 
# orchestrates model training, deployment, and monitoring across Google 
# Distributed Cloud Edge and centralized cloud infrastructure using Vertex AI.

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current project information
data "google_project" "current" {}

# Data source to get current client configuration
data "google_client_config" "current" {}

# =============================================================================
# CORE INFRASTRUCTURE - PROJECT APIS
# =============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "container.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# =============================================================================
# IAM SERVICE ACCOUNTS
# =============================================================================

# Service account for MLOps pipeline operations
resource "google_service_account" "mlops_pipeline_sa" {
  account_id   = "mlops-pipeline-sa-${random_string.suffix.result}"
  display_name = "MLOps Pipeline Service Account"
  description  = "Service account for MLOps pipeline operations including Vertex AI and storage access"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service account for edge inference workloads
resource "google_service_account" "edge_inference_sa" {
  account_id   = "edge-inference-sa-${random_string.suffix.result}"
  display_name = "Edge Inference Service Account"
  description  = "Service account for edge inference workloads and model serving"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service account for telemetry collection
resource "google_service_account" "telemetry_collector_sa" {
  account_id   = "telemetry-collector-sa-${random_string.suffix.result}"
  display_name = "Telemetry Collector Service Account"
  description  = "Service account for collecting and storing edge telemetry data"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# IAM POLICY BINDINGS
# =============================================================================

# MLOps Pipeline Service Account permissions
resource "google_project_iam_member" "mlops_pipeline_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/storage.admin",
    "roles/artifactregistry.reader",
    "roles/cloudbuild.builds.builder",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.mlops_pipeline_sa.email}"

  depends_on = [google_service_account.mlops_pipeline_sa]
}

# Edge Inference Service Account permissions
resource "google_project_iam_member" "edge_inference_permissions" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.edge_inference_sa.email}"

  depends_on = [google_service_account.edge_inference_sa]
}

# Telemetry Collector Service Account permissions
resource "google_project_iam_member" "telemetry_collector_permissions" {
  for_each = toset([
    "roles/storage.objectCreator",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.telemetry_collector_sa.email}"

  depends_on = [google_service_account.telemetry_collector_sa]
}

# =============================================================================
# CLOUD STORAGE BUCKETS
# =============================================================================

# Primary MLOps artifacts bucket for training data and model artifacts
resource "google_storage_bucket" "mlops_artifacts" {
  name     = "mlops-artifacts-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id

  # Enable versioning for model artifact tracking
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
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
      storage_class = "NEARLINE"
    }
  }

  # Uniform bucket-level access for security
  uniform_bucket_level_access = true

  # Labels for organization and cost tracking
  labels = {
    environment = var.environment
    component   = "mlops-storage"
    purpose     = "artifacts"
  }

  depends_on = [google_project_service.required_apis]
}

# Edge models bucket for distributed model deployment
resource "google_storage_bucket" "edge_models" {
  name     = "edge-models-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id

  # Enable versioning for model version tracking
  versioning {
    enabled = true
  }

  # Optimized lifecycle for edge model deployment
  lifecycle_rule {
    condition {
      age                        = 7
      num_newer_versions         = 3
      send_num_newer_versions_if_zero = false
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access for security
  uniform_bucket_level_access = true

  # CORS configuration for edge access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Labels for organization
  labels = {
    environment = var.environment
    component   = "edge-deployment"
    purpose     = "models"
  }

  depends_on = [google_project_service.required_apis]
}

# Telemetry data bucket for edge feedback collection
resource "google_storage_bucket" "telemetry_data" {
  name     = "telemetry-data-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id

  # Lifecycle management for telemetry data
  lifecycle_rule {
    condition {
      age = 365
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

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels for organization
  labels = {
    environment = var.environment
    component   = "telemetry"
    purpose     = "data-collection"
  }

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# GOOGLE KUBERNETES ENGINE (GKE) CLUSTER
# =============================================================================

# GKE cluster for edge simulation and inference workloads
resource "google_container_cluster" "edge_simulation_cluster" {
  name     = "edge-simulation-cluster-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = google_compute_network.mlops_network.name
  subnetwork = google_compute_subnetwork.mlops_subnet.name

  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Enable network policy for security
  network_policy {
    enabled = true
  }

  # Enable workload identity for secure pod authentication
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Cluster autoscaling configuration
  cluster_autoscaling {
    enabled = true
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 100
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 2
      maximum       = 1000
    }
  }

  # Monitoring and logging configuration
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
  }

  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = "2025-01-01T03:00:00Z"
      end_time   = "2025-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  # Security configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Labels for organization
  resource_labels = {
    environment = var.environment
    component   = "edge-simulation"
    purpose     = "inference-workloads"
  }

  depends_on = [
    google_project_service.required_apis,
    google_compute_network.mlops_network,
    google_compute_subnetwork.mlops_subnet
  ]
}

# Primary node pool for general workloads
resource "google_container_node_pool" "general_purpose_nodes" {
  name       = "general-purpose-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.edge_simulation_cluster.name
  node_count = 2

  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }

  # Node configuration
  node_config {
    preemptible  = var.use_preemptible_nodes
    machine_type = "e2-standard-4"
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    # Service account for nodes
    service_account = google_service_account.edge_inference_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Workload identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security settings
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Labels for node identification
    labels = {
      environment = var.environment
      node-pool   = "general-purpose"
    }

    # Taints for workload isolation (if needed)
    tags = ["mlops", "edge-inference"]
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_container_cluster.edge_simulation_cluster]
}

# High-performance node pool for ML inference workloads
resource "google_container_node_pool" "ml_inference_nodes" {
  name       = "ml-inference-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.edge_simulation_cluster.name
  node_count = 1

  # Autoscaling configuration
  autoscaling {
    min_node_count = 0
    max_node_count = 5
  }

  # Node configuration optimized for ML workloads
  node_config {
    preemptible  = var.use_preemptible_nodes
    machine_type = "n1-standard-8"  # Higher CPU for ML inference
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    # Service account for nodes
    service_account = google_service_account.edge_inference_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Workload identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security settings
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Labels for node identification
    labels = {
      environment = var.environment
      node-pool   = "ml-inference"
      workload    = "high-performance"
    }

    # Taints to ensure only ML workloads are scheduled here
    taint {
      key    = "ml-inference"
      value  = "dedicated"
      effect = "NO_SCHEDULE"
    }

    tags = ["mlops", "ml-inference", "high-performance"]
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_container_cluster.edge_simulation_cluster]
}

# =============================================================================
# NETWORK INFRASTRUCTURE
# =============================================================================

# VPC network for MLOps infrastructure
resource "google_compute_network" "mlops_network" {
  name                    = "mlops-network-${random_string.suffix.result}"
  project                 = var.project_id
  auto_create_subnetworks = false
  description             = "VPC network for MLOps pipeline infrastructure"

  depends_on = [google_project_service.required_apis]
}

# Subnet for GKE cluster and other resources
resource "google_compute_subnetwork" "mlops_subnet" {
  name          = "mlops-subnet-${random_string.suffix.result}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.mlops_network.name
  ip_cidr_range = "10.0.0.0/16"
  description   = "Subnet for MLOps cluster and infrastructure"

  # Secondary IP ranges for GKE
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }

  # Enable private Google access for nodes without external IPs
  private_ip_google_access = true

  depends_on = [google_compute_network.mlops_network]
}

# Cloud Router for NAT gateway
resource "google_compute_router" "mlops_router" {
  name    = "mlops-router-${random_string.suffix.result}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.mlops_network.id

  depends_on = [google_compute_network.mlops_network]
}

# NAT gateway for outbound internet access from private nodes
resource "google_compute_router_nat" "mlops_nat" {
  name   = "mlops-nat-${random_string.suffix.result}"
  router = google_compute_router.mlops_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [google_compute_router.mlops_router]
}

# Firewall rules for cluster communication
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-${random_string.suffix.result}"
  project = var.project_id
  network = google_compute_network.mlops_network.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
  description   = "Allow internal communication within the VPC"

  depends_on = [google_compute_network.mlops_network]
}

# =============================================================================
# CLOUD MONITORING DASHBOARD
# =============================================================================

# MLOps monitoring dashboard for observability
resource "google_monitoring_dashboard" "mlops_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Edge MLOps Pipeline Dashboard"
    gridLayout = {
      widgets = [
        {
          title = "Edge Inference Request Rate"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"inference-server\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Requests/sec"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Model Prediction Latency"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_container\" AND metric.type=\"custom.googleapis.com/inference/latency\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Latency (ms)"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Storage Bucket Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/storage/total_bytes\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Storage (bytes)"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "GKE Cluster Resource Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_cluster\" AND metric.type=\"kubernetes.io/cluster/cpu/core_usage_time\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "CPU cores"
              scale = "LINEAR"
            }
          }
        }
      ]
    }
  })

  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD MONITORING ALERT POLICIES
# =============================================================================

# Notification channel for alerts (email)
resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "MLOps Alert Email"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for edge inference service health
resource "google_monitoring_alert_policy" "edge_service_health" {
  display_name = "Edge Inference Service Down"
  project      = var.project_id

  documentation {
    content = "Edge inference service is not responding to health checks. This may indicate a critical issue with model serving infrastructure."
  }

  conditions {
    display_name = "Edge service health check failure"

    condition_threshold {
      filter         = "resource.type=\"k8s_container\" AND resource.labels.container_name=\"inference-server\""
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 1
      duration       = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.email_channel.id]

  enabled = true

  depends_on = [google_monitoring_notification_channel.email_channel]
}

# Alert policy for high model prediction latency
resource "google_monitoring_alert_policy" "high_prediction_latency" {
  display_name = "High Model Prediction Latency"
  project      = var.project_id

  documentation {
    content = "Model prediction latency is higher than acceptable thresholds. Consider scaling inference infrastructure or optimizing model performance."
  }

  conditions {
    display_name = "High inference latency"

    condition_threshold {
      filter         = "resource.type=\"k8s_container\" AND metric.type=\"custom.googleapis.com/inference/latency\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 1000  # 1 second threshold
      duration       = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  notification_channels = [google_monitoring_notification_channel.email_channel.id]

  enabled = true

  depends_on = [google_monitoring_notification_channel.email_channel]
}

# =============================================================================
# CLOUD FUNCTION FOR MODEL UPDATES
# =============================================================================

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "function-source-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    component   = "cloud-function"
    purpose     = "source-code"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Function source code archive
data "archive_file" "model_updater_source" {
  type        = "zip"
  output_path = "/tmp/model_updater_source.zip"
  source {
    content  = file("${path.module}/functions/model_updater.py")
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "model_updater_source" {
  name   = "model_updater_source.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.model_updater_source.output_path

  depends_on = [
    google_storage_bucket.function_source,
    data.archive_file.model_updater_source
  ]
}

# Cloud Function for automated model updates
resource "google_cloudfunctions_function" "model_updater" {
  name    = "edge-model-updater-${random_string.suffix.result}"
  project = var.project_id
  region  = var.region

  description = "Automated model update function for edge deployments"

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.model_updater_source.name

  trigger {
    http_trigger {
      url = null
    }
  }

  entry_point = "update_edge_models"
  runtime     = "python39"

  timeout               = 300
  available_memory_mb   = 512
  max_instances         = 10
  service_account_email = google_service_account.mlops_pipeline_sa.email

  environment_variables = {
    PROJECT_ID         = var.project_id
    EDGE_MODELS_BUCKET = google_storage_bucket.edge_models.name
    MLOPS_BUCKET       = google_storage_bucket.mlops_artifacts.name
  }

  labels = {
    environment = var.environment
    component   = "model-update"
    purpose     = "automation"
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.model_updater_source,
    google_service_account.mlops_pipeline_sa
  ]
}

# IAM binding to allow HTTP invocation of the function
resource "google_cloudfunctions_function_iam_member" "model_updater_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.model_updater.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.mlops_pipeline_sa.email}"

  depends_on = [google_cloudfunctions_function.model_updater]
}

# =============================================================================
# KUBERNETES CONFIGURATIONS
# =============================================================================

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${google_container_cluster.edge_simulation_cluster.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.edge_simulation_cluster.master_auth.0.cluster_ca_certificate)
}

# Namespace for edge inference workloads
resource "kubernetes_namespace" "edge_inference" {
  metadata {
    name = "edge-inference"
    labels = {
      app         = "edge-inference"
      environment = var.environment
    }
  }

  depends_on = [google_container_cluster.edge_simulation_cluster]
}

# Kubernetes service account for edge inference with workload identity
resource "kubernetes_service_account" "edge_inference_ksa" {
  metadata {
    name      = "edge-inference-ksa"
    namespace = kubernetes_namespace.edge_inference.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.edge_inference_sa.email
    }
  }

  depends_on = [kubernetes_namespace.edge_inference]
}

# Bind Kubernetes service account to Google service account
resource "google_service_account_iam_member" "edge_inference_workload_identity" {
  service_account_id = google_service_account.edge_inference_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[edge-inference/edge-inference-ksa]"

  depends_on = [
    google_service_account.edge_inference_sa,
    kubernetes_service_account.edge_inference_ksa
  ]
}

# ConfigMap for edge inference configuration
resource "kubernetes_config_map" "edge_inference_config" {
  metadata {
    name      = "edge-inference-config"
    namespace = kubernetes_namespace.edge_inference.metadata[0].name
  }

  data = {
    "MODEL_BUCKET"         = google_storage_bucket.edge_models.name
    "PROJECT_ID"           = var.project_id
    "TELEMETRY_ENDPOINT"   = "http://telemetry-collector.edge-inference.svc.cluster.local"
    "MODEL_VERSION"        = "v1"
    "INFERENCE_TIMEOUT"    = "30"
    "MAX_BATCH_SIZE"       = "32"
    "HEALTH_CHECK_INTERVAL" = "10"
  }

  depends_on = [kubernetes_namespace.edge_inference]
}