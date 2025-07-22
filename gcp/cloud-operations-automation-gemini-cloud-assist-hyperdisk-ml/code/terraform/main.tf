# Main Terraform configuration for Cloud Operations Automation
# with Gemini Cloud Assist and Hyperdisk ML

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix = random_id.suffix.hex
  
  # Resource names with unique suffix
  cluster_name_full    = "${var.cluster_name}-${local.suffix}"
  hyperdisk_name_full  = "${var.hyperdisk_name}-${local.suffix}"
  function_name_full   = "${var.function_name}-${local.suffix}"
  bucket_name_full     = "${var.dataset_bucket_name}-${var.project_id}-${local.suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    component = "ml-operations-automation"
    version   = "1.0"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Hyperdisk ML volume for high-performance ML storage
resource "google_compute_disk" "hyperdisk_ml" {
  name = local.hyperdisk_name_full
  type = "hyperdisk-ml"
  zone = var.zone
  size = var.hyperdisk_size_gb
  
  # Hyperdisk ML specific configuration
  provisioned_iops       = null # Not applicable for Hyperdisk ML
  provisioned_throughput = var.hyperdisk_provisioned_throughput
  
  labels = merge(local.common_labels, {
    storage-type = "hyperdisk-ml"
    purpose      = "ml-workloads"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create GKE cluster for ML workloads
resource "google_container_cluster" "ml_ops_cluster" {
  name     = local.cluster_name_full
  location = var.zone
  
  # Remove default node pool to use custom node pools
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # IP allocation for pods and services
  dynamic "ip_allocation_policy" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      cluster_ipv4_cidr_block  = var.pods_ipv4_cidr_block
      services_ipv4_cidr_block = var.services_ipv4_cidr_block
    }
  }
  
  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled  = true
      provider = "CALICO"
    }
  }
  
  # Addons configuration
  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }
  
  # Cluster features
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Maintenance window
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T09:00:00Z"
      end_time   = "2023-01-01T17:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }
  
  resource_labels = merge(local.common_labels, {
    cluster-type = "ml-operations"
  })
  
  depends_on = [google_project_service.required_apis]
}

# CPU node pool for general ML workloads
resource "google_container_node_pool" "cpu_pool" {
  name       = "cpu-pool"
  location   = var.zone
  cluster    = google_container_cluster.ml_ops_cluster.name
  
  node_count = var.cluster_initial_node_count
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.cluster_min_nodes
    max_node_count = var.cluster_max_nodes
  }
  
  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.cluster_machine_type
    
    # Google Cloud service account
    service_account = google_service_account.vertex_ai_agent.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels and metadata
    labels = merge(local.common_labels, {
      node-type = "cpu"
      workload  = "ml-training"
    })
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  depends_on = [google_container_cluster.ml_ops_cluster]
}

# GPU node pool for intensive ML training
resource "google_container_node_pool" "gpu_pool" {
  name       = "gpu-pool"
  location   = var.zone
  cluster    = google_container_cluster.ml_ops_cluster.name
  
  initial_node_count = 0
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.gpu_min_nodes
    max_node_count = var.gpu_max_nodes
  }
  
  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.gpu_machine_type
    
    # GPU configuration
    guest_accelerator {
      type  = var.gpu_accelerator_type
      count = var.gpu_accelerator_count
    }
    
    # Google Cloud service account
    service_account = google_service_account.vertex_ai_agent.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels and metadata
    labels = merge(local.common_labels, {
      node-type = "gpu"
      workload  = "ml-training-intensive"
    })
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Taints for GPU nodes
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  depends_on = [google_container_cluster.ml_ops_cluster]
}

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_agent" {
  account_id   = "vertex-ai-agent-${local.suffix}"
  display_name = "Vertex AI Operations Agent"
  description  = "Service account for Vertex AI operations and ML automation"
}

# IAM bindings for Vertex AI agent
resource "google_project_iam_member" "vertex_ai_agent_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/monitoring.metricWriter",
    "roles/storage.objectViewer",
    "roles/compute.viewer",
    "roles/container.developer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_agent.email}"
}

# Cloud Storage bucket for ML datasets
resource "google_storage_bucket" "ml_datasets" {
  name          = local.bucket_name_full
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "ml-datasets"
  })
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for dataset bucket access
resource "google_storage_bucket_iam_member" "vertex_ai_bucket_access" {
  bucket = google_storage_bucket.ml_datasets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.vertex_ai_agent.email}"
}

# Archive function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Function for ML operations automation
resource "google_cloudfunctions_function" "ml_ops_automation" {
  name                  = local.function_name_full
  description          = "AI-powered ML operations automation function"
  runtime              = "python39"
  available_memory_mb  = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "ml_ops_automation"
  service_account_email = google_service_account.vertex_ai_agent.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    https_trigger {}
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
    CLUSTER_NAME = local.cluster_name_full
    HYPERDISK_NAME = local.hyperdisk_name_full
  }
  
  labels = merge(local.common_labels, {
    function-type = "ml-automation"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.function_name_full}-source-${local.suffix}"
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
}

# Upload function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Scheduler job for automated ML operations
resource "google_cloud_scheduler_job" "ml_ops_scheduler" {
  name             = "ml-ops-scheduler-${local.suffix}"
  description      = "Automated ML operations scheduling"
  schedule         = var.scheduler_frequency
  time_zone        = "UTC"
  attempt_deadline = "180s"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.ml_ops_automation.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled_optimization"
      type    = "ml_workload_analysis"
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.ml_ops_automation
  ]
}

# Performance monitoring scheduler
resource "google_cloud_scheduler_job" "performance_monitor" {
  name             = "performance-monitor-${local.suffix}"
  description      = "Hyperdisk ML performance monitoring"
  schedule         = var.performance_monitor_frequency
  time_zone        = "UTC"
  attempt_deadline = "180s"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.ml_ops_automation.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "performance_check"
      type    = "hyperdisk_monitoring"
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.ml_ops_automation
  ]
}

# Custom log-based metrics for ML workload monitoring
resource "google_logging_metric" "ml_training_duration" {
  name   = "ml_training_duration_${local.suffix}"
  filter = "resource.type=\"gke_container\" AND jsonPayload.event_type=\"training_complete\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "ML Training Duration"
  }
  
  label_extractors = {
    job_name = "EXTRACT(jsonPayload.job_name)"
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_logging_metric" "storage_throughput" {
  name   = "storage_throughput_${local.suffix}"
  filter = "resource.type=\"gce_disk\" AND jsonPayload.disk_type=\"hyperdisk-ml\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Hyperdisk ML Throughput Utilization"
  }
  
  label_extractors = {
    disk_name = "EXTRACT(resource.labels.disk_name)"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alerting policy for ML workload anomalies
resource "google_monitoring_alert_policy" "ml_workload_performance" {
  count = var.enable_alerting_policies ? 1 : 0
  
  display_name = "ML Workload Performance Alert - ${local.suffix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High training duration"
    
    condition_threshold {
      filter         = "metric.type=\"logging.googleapis.com/user/ml_training_duration_${local.suffix}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 3600
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.ml_training_duration
  ]
}

# Kubernetes configurations
# Storage class for Hyperdisk ML
resource "kubernetes_storage_class" "hyperdisk_ml" {
  metadata {
    name = "hyperdisk-ml-storage"
    labels = local.common_labels
  }
  
  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy        = "Retain"
  allow_volume_expansion = true
  
  parameters = {
    type              = "hyperdisk-ml"
    replication-type  = "regional"
  }
  
  depends_on = [google_container_node_pool.cpu_pool]
}

# ConfigMap for Vertex AI agent configuration
resource "kubernetes_config_map" "vertex_ai_config" {
  metadata {
    name      = "vertex-ai-config"
    namespace = "default"
    labels    = local.common_labels
  }
  
  data = {
    "config.json" = jsonencode({
      agent_config = {
        name = "ml-ops-automation-agent"
        type = "operations-optimizer"
        capabilities = [
          "workload-analysis",
          "predictive-scaling",
          "cost-optimization",
          "performance-monitoring"
        ]
      }
    })
  }
  
  depends_on = [google_container_node_pool.cpu_pool]
}

# Sample ML training job (commented out by default)
/*
resource "kubernetes_job" "ml_training_sample" {
  metadata {
    name      = "ml-training-hyperdisk-sample"
    namespace = "default"
    labels    = local.common_labels
  }
  
  spec {
    template {
      metadata {
        labels = local.common_labels
      }
      
      spec {
        container {
          name  = "ml-trainer"
          image = "gcr.io/google-samples/hello-app:1.0"
          command = ["/bin/sh"]
          args = ["-c", "echo 'ML Training with Hyperdisk ML'; sleep 300"]
          
          volume_mount {
            name       = "ml-data"
            mount_path = "/data"
          }
          
          env {
            name  = "TRAINING_DATA_PATH"
            value = "/data"
          }
          
          env {
            name  = "PROJECT_ID"
            value = var.project_id
          }
        }
        
        volume {
          name = "ml-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.hyperdisk_ml_pvc.metadata[0].name
          }
        }
        
        restart_policy = "Never"
      }
    }
  }
  
  depends_on = [
    kubernetes_persistent_volume_claim.hyperdisk_ml_pvc,
    kubernetes_storage_class.hyperdisk_ml
  ]
}

resource "kubernetes_persistent_volume_claim" "hyperdisk_ml_pvc" {
  metadata {
    name      = "hyperdisk-ml-pvc"
    namespace = "default"
    labels    = local.common_labels
  }
  
  spec {
    access_modes = ["ReadOnlyMany"]
    storage_class_name = kubernetes_storage_class.hyperdisk_ml.metadata[0].name
    
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
  
  depends_on = [kubernetes_storage_class.hyperdisk_ml]
}
*/