# Random suffix for unique resource naming
# This ensures resource names are unique across deployments
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.resource_prefix}-${random_id.suffix.hex}"
  
  # Common labels for all resources to support governance and cost allocation
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    app_name    = var.app_name
  })
  
  # Required Google Cloud APIs for the multi-environment testing pipeline
  # These APIs enable GKE, Cloud Build, Cloud Deploy, Artifact Registry, and monitoring
  required_apis = [
    "container.googleapis.com",           # Google Kubernetes Engine
    "cloudbuild.googleapis.com",          # Cloud Build for CI/CD
    "clouddeploy.googleapis.com",         # Cloud Deploy for progressive delivery
    "artifactregistry.googleapis.com",    # Artifact Registry for container images
    "monitoring.googleapis.com",          # Cloud Monitoring for observability
    "logging.googleapis.com",             # Cloud Logging for log aggregation
    "cloudresourcemanager.googleapis.com" # Resource Manager for project operations
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.key
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Artifact Registry Repository for container images
resource "google_artifact_registry_repository" "container_repo" {
  provider = google-beta
  
  location      = var.region
  repository_id = "${local.name_prefix}-repo"
  description   = "Container repository for multi-environment testing pipeline"
  format        = var.artifact_registry_format
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Service Account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${local.name_prefix}-gke-nodes"
  display_name = "GKE Nodes Service Account for ${local.name_prefix}"
  description  = "Service account for GKE node pools in multi-environment pipeline"
}

# IAM binding for GKE node service account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/container.nodeServiceAgent"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# GKE Development Cluster
resource "google_container_cluster" "dev" {
  name     = "${local.name_prefix}-dev"
  location = var.zone
  
  # Cluster configuration
  initial_node_count       = var.dev_cluster_config.node_count
  remove_default_node_pool = true
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Security configuration
  enable_shielded_nodes = var.enable_shielded_nodes
  
  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    
    managed_prometheus {
      enabled = true
    }
  }
  
  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    cluster-environment = "development"
  })
  
  depends_on = [google_project_service.required_apis]
}

# GKE Development Node Pool
resource "google_container_node_pool" "dev_nodes" {
  name       = "${local.name_prefix}-dev-nodes"
  location   = var.zone
  cluster    = google_container_cluster.dev.name
  node_count = var.dev_cluster_config.node_count
  
  node_config {
    machine_type    = var.dev_cluster_config.machine_type
    disk_size_gb    = var.dev_cluster_config.disk_size_gb
    disk_type       = var.dev_cluster_config.disk_type
    service_account = google_service_account.gke_nodes.email
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Shielded Instance configuration
    dynamic "shielded_instance_config" {
      for_each = var.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }
    
    # Workload Identity
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
    
    labels = merge(local.common_labels, {
      environment = "development"
    })
  }
  
  # Auto-upgrade and auto-repair
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# GKE Staging Cluster
resource "google_container_cluster" "staging" {
  name     = "${local.name_prefix}-staging"
  location = var.zone
  
  # Cluster configuration
  initial_node_count       = var.staging_cluster_config.node_count
  remove_default_node_pool = true
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Security configuration
  enable_shielded_nodes = var.enable_shielded_nodes
  
  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    
    managed_prometheus {
      enabled = true
    }
  }
  
  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    cluster-environment = "staging"
  })
  
  depends_on = [google_project_service.required_apis]
}

# GKE Staging Node Pool
resource "google_container_node_pool" "staging_nodes" {
  name       = "${local.name_prefix}-staging-nodes"
  location   = var.zone
  cluster    = google_container_cluster.staging.name
  node_count = var.staging_cluster_config.node_count
  
  node_config {
    machine_type    = var.staging_cluster_config.machine_type
    disk_size_gb    = var.staging_cluster_config.disk_size_gb
    disk_type       = var.staging_cluster_config.disk_type
    service_account = google_service_account.gke_nodes.email
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Shielded Instance configuration
    dynamic "shielded_instance_config" {
      for_each = var.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }
    
    # Workload Identity
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
    
    labels = merge(local.common_labels, {
      environment = "staging"
    })
  }
  
  # Auto-upgrade and auto-repair
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# GKE Production Cluster
resource "google_container_cluster" "prod" {
  name     = "${local.name_prefix}-prod"
  location = var.zone
  
  # Cluster configuration
  initial_node_count       = var.prod_cluster_config.node_count
  remove_default_node_pool = true
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy (enforced in production)
  network_policy {
    enabled = true
  }
  
  # Security configuration (enhanced for production)
  enable_shielded_nodes = true
  
  # Binary Authorization (production security)
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  
  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "API_SERVER"]
  }
  
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    
    managed_prometheus {
      enabled = true
    }
  }
  
  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    cluster-environment = "production"
  })
  
  depends_on = [google_project_service.required_apis]
}

# GKE Production Node Pool
resource "google_container_node_pool" "prod_nodes" {
  name       = "${local.name_prefix}-prod-nodes"
  location   = var.zone
  cluster    = google_container_cluster.prod.name
  node_count = var.prod_cluster_config.node_count
  
  node_config {
    machine_type    = var.prod_cluster_config.machine_type
    disk_size_gb    = var.prod_cluster_config.disk_size_gb
    disk_type       = var.prod_cluster_config.disk_type
    service_account = google_service_account.gke_nodes.email
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Shielded Instance configuration (enforced in production)
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Workload Identity (enforced in production)
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    labels = merge(local.common_labels, {
      environment = "production"
    })
  }
  
  # Auto-upgrade and auto-repair
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service Account for Cloud Build
resource "google_service_account" "cloud_build" {
  account_id   = "${local.name_prefix}-cloud-build"
  display_name = "Cloud Build Service Account for ${local.name_prefix}"
  description  = "Service account for Cloud Build in multi-environment pipeline"
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloud_build_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/clouddeploy.releaser",
    "roles/container.developer",
    "roles/storage.admin",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Service Account for Cloud Deploy
resource "google_service_account" "cloud_deploy" {
  account_id   = "${local.name_prefix}-cloud-deploy"
  display_name = "Cloud Deploy Service Account for ${local.name_prefix}"
  description  = "Service account for Cloud Deploy operations"
}

# IAM bindings for Cloud Deploy service account
resource "google_project_iam_member" "cloud_deploy_roles" {
  for_each = toset([
    "roles/clouddeploy.operator",
    "roles/container.clusterViewer",
    "roles/container.developer",
    "roles/artifactregistry.reader",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_deploy.email}"
}

# Cloud Deploy Delivery Pipeline
# This pipeline orchestrates progressive delivery across development, staging, and production environments
# Each stage can include verification steps, approval gates, and rollback capabilities
resource "google_clouddeploy_delivery_pipeline" "pipeline" {
  provider = google-beta
  
  location = var.region
  name     = "${local.name_prefix}-pipeline"
  
  description = "Multi-environment testing pipeline for progressive delivery"
  
  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.dev.name
      profiles  = ["dev"]
      
      dynamic "strategy" {
        for_each = var.enable_verification ? [1] : []
        content {
          standard {
            verify = true
          }
        }
      }
    }
    
    stages {
      target_id = google_clouddeploy_target.staging.name
      profiles  = ["staging"]
      
      dynamic "strategy" {
        for_each = var.enable_verification ? [1] : []
        content {
          standard {
            verify = true
          }
        }
      }
    }
    
    stages {
      target_id = google_clouddeploy_target.prod.name
      profiles  = ["prod"]
      
      dynamic "strategy" {
        for_each = var.enable_verification ? [1] : []
        content {
          standard {
            verify = true
          }
        }
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Deploy Target - Development
resource "google_clouddeploy_target" "dev" {
  provider = google-beta
  
  location = var.region
  name     = "dev"
  
  description = "Development environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.dev.name}"
  }
  
  execution_configs {
    usages            = ["RENDER", "DEPLOY", "VERIFY"]
    service_account   = google_service_account.cloud_deploy.email
    artifact_storage  = "gs://${google_storage_bucket.deploy_artifacts.name}/dev"
  }
  
  labels = merge(local.common_labels, {
    target-environment = "development"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Deploy Target - Staging
resource "google_clouddeploy_target" "staging" {
  provider = google-beta
  
  location = var.region
  name     = "staging"
  
  description = "Staging environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.staging.name}"
  }
  
  execution_configs {
    usages            = ["RENDER", "DEPLOY", "VERIFY"]
    service_account   = google_service_account.cloud_deploy.email
    artifact_storage  = "gs://${google_storage_bucket.deploy_artifacts.name}/staging"
  }
  
  require_approval = false
  
  labels = merge(local.common_labels, {
    target-environment = "staging"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Deploy Target - Production
resource "google_clouddeploy_target" "prod" {
  provider = google-beta
  
  location = var.region
  name     = "prod"
  
  description = "Production environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.prod.name}"
  }
  
  execution_configs {
    usages            = ["RENDER", "DEPLOY", "VERIFY"]
    service_account   = google_service_account.cloud_deploy.email
    artifact_storage  = "gs://${google_storage_bucket.deploy_artifacts.name}/prod"
  }
  
  require_approval = var.require_approval_prod
  
  labels = merge(local.common_labels, {
    target-environment = "production"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for deployment artifacts
resource "google_storage_bucket" "deploy_artifacts" {
  name     = "${local.name_prefix}-deploy-artifacts"
  location = var.region
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning
  versioning {
    enabled = true
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.common_labels
}

# Cloud Build Trigger for automated builds and deployments
# This trigger activates when code is pushed to the main branch and
# executes the cloudbuild.yaml pipeline configuration
resource "google_cloudbuild_trigger" "main_trigger" {
  name        = "${local.name_prefix}-main-trigger"
  description = "Trigger for main branch builds and deployments"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    
    push {
      branch = "^main$"
    }
  }
  
  filename = "cloudbuild.yaml"
  
  substitutions = {
    _ARTIFACT_REGISTRY_REPO = google_artifact_registry_repository.container_repo.name
    _DEPLOY_PIPELINE_NAME   = google_clouddeploy_delivery_pipeline.pipeline.name
    _REGION                 = var.region
    _APP_NAME               = var.app_name
    _PROJECT_ID             = var.project_id
  }
  
  service_account = google_service_account.cloud_build.id
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "pipeline_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "${local.name_prefix} Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "GKE Container CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=~\"${local.name_prefix}.*\""
                      aggregation = {
                        alignmentPeriod     = "60s"
                        perSeriesAligner    = "ALIGN_RATE"
                        crossSeriesReducer  = "REDUCE_MEAN"
                        groupByFields       = ["resource.labels.cluster_name"]
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
            title = "Cloud Deploy Release Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_deploy_delivery_pipeline\" AND resource.labels.pipeline_id=\"${google_clouddeploy_delivery_pipeline.pipeline.name}\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_COUNT"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring Alert Policy for failed deployments
resource "google_monitoring_alert_policy" "failed_deployments" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "${local.name_prefix} Failed Deployments"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Deploy Failed Releases"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_deploy_delivery_pipeline\" AND resource.labels.pipeline_id=\"${google_clouddeploy_delivery_pipeline.pipeline.name}\" AND metric.type=\"clouddeploy.googleapis.com/delivery_pipeline/failed_releases\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}