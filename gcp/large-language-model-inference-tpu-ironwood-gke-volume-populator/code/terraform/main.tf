# ================================================================
# Large Language Model Inference with TPU Ironwood and GKE Volume Populator
# 
# This Terraform configuration deploys a high-performance LLM inference
# pipeline using Google's TPU Ironwood accelerators with GKE Volume Populator
# for optimized model data transfer from Cloud Storage to Parallelstore.
# 
# Key Components:
# - GKE cluster with TPU Ironwood support
# - Parallelstore for high-performance model storage
# - Cloud Storage for model artifact repository
# - IAM service accounts with Workload Identity
# - Cloud Monitoring dashboard for performance tracking
# ================================================================

# ----------------------------------------------------------------
# Local Values
# ----------------------------------------------------------------
locals {
  # Generate unique suffixes for resource naming
  random_suffix = lower(random_id.suffix.hex)
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    project     = "llm-inference"
    recipe      = "tpu-ironwood-inference"
    managed-by  = "terraform"
  }
  
  # Service account email
  service_account_email = "${google_service_account.tpu_inference.account_id}@${var.project_id}.iam.gserviceaccount.com"
}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ----------------------------------------------------------------
# Enable Required Google Cloud APIs
# ----------------------------------------------------------------
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "parallelstore.googleapis.com",
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy         = false
  disable_dependent_services = false
}

# ----------------------------------------------------------------
# Cloud Storage Bucket for Model Artifacts
# ----------------------------------------------------------------
resource "google_storage_bucket" "model_storage" {
  name     = "${var.bucket_name_prefix}-${local.random_suffix}"
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Enable versioning for model artifact management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for older versions
  lifecycle_rule {
    condition {
      age                   = 30
      with_state           = "ARCHIVED"
      num_newer_versions   = 3
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ----------------------------------------------------------------
# IAM Service Account for TPU Inference Workloads
# ----------------------------------------------------------------
resource "google_service_account" "tpu_inference" {
  project      = var.project_id
  account_id   = "${var.service_account_name}-${local.random_suffix}"
  display_name = "TPU Inference Service Account"
  description  = "Service account for LLM inference with TPU Ironwood accelerators"
  
  depends_on = [google_project_service.required_apis]
}

# Grant TPU Admin permissions
resource "google_project_iam_member" "tpu_admin" {
  project = var.project_id
  role    = "roles/tpu.admin"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.tpu_inference]
}

# Grant Storage Object Viewer permissions
resource "google_project_iam_member" "storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.tpu_inference]
}

# Grant Parallelstore Admin permissions
resource "google_project_iam_member" "parallelstore_admin" {
  project = var.project_id
  role    = "roles/parallelstore.admin"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.tpu_inference]
}

# Grant Kubernetes Engine Developer role for GKE access
resource "google_project_iam_member" "gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.tpu_inference]
}

# ----------------------------------------------------------------
# GKE Cluster with TPU Ironwood Support
# ----------------------------------------------------------------
resource "google_container_cluster" "tpu_cluster" {
  name     = "${var.cluster_name}-${local.random_suffix}"
  location = var.zone
  project  = var.project_id
  
  # Remove default node pool (we'll create custom node pools)
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Enable Workload Identity for secure service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Enable network policy for enhanced security
  network_policy {
    enabled = true
  }
  
  # Enable IP aliasing for better networking performance
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.cluster_ipv4_cidr
    services_ipv4_cidr_block = var.services_ipv4_cidr
  }
  
  # Enable cluster autoscaling
  cluster_autoscaling {
    enabled = true
    
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 100
    }
    
    resource_limits {
      resource_type = "memory"
      minimum       = 1
      maximum       = 1000
    }
    
    # Auto-provisioning node pool defaults
    auto_provisioning_defaults {
      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
      
      service_account = local.service_account_email
      
      management {
        auto_repair  = true
        auto_upgrade = true
      }
    }
  }
  
  # Add-ons configuration
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    http_load_balancing {
      disabled = false
    }
    
    network_policy_config {
      disabled = false
    }
    
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  
  # Enable logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }
  
  # Resource labels
  resource_labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.tpu_inference
  ]
}

# ----------------------------------------------------------------
# Standard Node Pool for System Components
# ----------------------------------------------------------------
resource "google_container_node_pool" "standard_pool" {
  name       = "standard-pool"
  cluster    = google_container_cluster.tpu_cluster.name
  location   = var.zone
  project    = var.project_id
  node_count = var.standard_node_count
  
  # Node configuration
  node_config {
    machine_type = var.standard_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"
    
    # Enable auto-repair and auto-upgrade
    management {
      auto_repair  = true
      auto_upgrade = true
    }
    
    # OAuth scopes for node access
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    service_account = local.service_account_email
    
    labels = merge(local.common_labels, {
      pool-type = "standard"
    })
    
    tags = ["gke-node", "standard-pool"]
  }
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.standard_min_nodes
    max_node_count = var.standard_max_nodes
  }
  
  depends_on = [google_container_cluster.tpu_cluster]
}

# ----------------------------------------------------------------
# TPU Node Pool for Inference Workloads
# ----------------------------------------------------------------
resource "google_container_node_pool" "tpu_pool" {
  name       = "tpu-ironwood-pool"
  cluster    = google_container_cluster.tpu_cluster.name
  location   = var.zone
  project    = var.project_id
  node_count = var.tpu_node_count
  
  # TPU node configuration
  node_config {
    machine_type = var.tpu_machine_type
    disk_size_gb = 100
    disk_type    = "pd-ssd"
    
    # TPU-specific configuration
    guest_accelerator {
      type  = var.tpu_accelerator_type
      count = var.tpu_accelerator_count
    }
    
    # Enable auto-repair and auto-upgrade
    management {
      auto_repair  = true
      auto_upgrade = true
    }
    
    # OAuth scopes for TPU access
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/tpu"
    ]
    
    service_account = local.service_account_email
    
    labels = merge(local.common_labels, {
      pool-type = "tpu"
    })
    
    tags = ["gke-node", "tpu-pool"]
    
    # Taints to ensure only TPU workloads are scheduled
    taint {
      key    = "google.com/tpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }
  }
  
  # Autoscaling for TPU nodes
  autoscaling {
    min_node_count = var.tpu_min_nodes
    max_node_count = var.tpu_max_nodes
  }
  
  depends_on = [google_container_cluster.tpu_cluster]
}

# ----------------------------------------------------------------
# Parallelstore Instance for High-Performance Model Storage
# ----------------------------------------------------------------
resource "google_parallelstore_instance" "model_storage" {
  instance_id = "${var.parallelstore_name}-${local.random_suffix}"
  location    = var.zone
  project     = var.project_id
  
  capacity_gib     = var.parallelstore_capacity_gib
  performance_tier = var.parallelstore_performance_tier
  
  description = "High-performance parallel storage for LLM model weights and inference data"
  
  # Network configuration
  network = "projects/${var.project_id}/global/networks/default"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ----------------------------------------------------------------
# Workload Identity Binding
# ----------------------------------------------------------------
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.tpu_inference.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
  
  depends_on = [google_service_account.tpu_inference]
}

# ----------------------------------------------------------------
# Cloud Monitoring Dashboard for TPU Performance Tracking
# ----------------------------------------------------------------
resource "google_monitoring_dashboard" "tpu_inference_dashboard" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "TPU Ironwood LLM Inference Dashboard"
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
                      filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
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
            title = "GKE Cluster Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_cluster\" AND metric.type=\"kubernetes.io/container/cpu/core_usage_time\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.cluster_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Cores"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Parallelstore Throughput"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"parallelstore_instance\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Throughput (MB/s)"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# ----------------------------------------------------------------
# Storage Bucket IAM for Service Account Access
# ----------------------------------------------------------------
resource "google_storage_bucket_iam_member" "model_bucket_access" {
  bucket = google_storage_bucket.model_storage.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.service_account_email}"
  
  depends_on = [
    google_storage_bucket.model_storage,
    google_service_account.tpu_inference
  ]
}

# ----------------------------------------------------------------
# Cloud Logging Sink for Enhanced Observability
# ----------------------------------------------------------------
resource "google_logging_project_sink" "tpu_inference_logs" {
  name        = "tpu-inference-logs-${local.random_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.model_storage.name}/logs"
  
  # Filter for TPU and inference-related logs
  filter = <<-EOT
    resource.type="k8s_cluster" OR
    resource.type="gce_instance" OR
    resource.type="parallelstore_instance"
    AND (
      labels.app="tpu-ironwood-inference" OR
      resource.labels.cluster_name="${google_container_cluster.tpu_cluster.name}"
    )
  EOT
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [
    google_storage_bucket.model_storage,
    google_container_cluster.tpu_cluster
  ]
}

# Grant the logging sink writer permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.model_storage.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.tpu_inference_logs.writer_identity
  
  depends_on = [google_logging_project_sink.tpu_inference_logs]
}