# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  suffix = var.random_suffix != null ? var.random_suffix : random_id.suffix.hex
  
  # Resource names
  cluster_dev_name    = "${var.name_prefix}-dev-cluster-${local.suffix}"
  cluster_staging_name = "${var.name_prefix}-staging-cluster-${local.suffix}"
  cluster_prod_name   = "${var.name_prefix}-prod-cluster-${local.suffix}"
  
  repo_name        = "${var.name_prefix}-repo-${local.suffix}"
  pipeline_name    = "${var.pipeline_name}-${local.suffix}"
  bucket_name      = "${var.name_prefix}-artifacts-${var.project_id}-${local.suffix}"
  
  # Container image
  container_image = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${local.repo_name}/${var.app_name}:latest"
  
  # Common labels
  common_labels = merge(var.labels, {
    created-by = "terraform"
    project-id = var.project_id
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "clouddeploy.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com"
  ])
  
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "app_repo" {
  depends_on = [google_project_service.required_apis]
  
  location      = var.region
  repository_id = local.repo_name
  description   = "Repository for multi-environment deployment demo"
  format        = "DOCKER"
  
  labels = local.common_labels
}

# Create Cloud Storage bucket for deployment artifacts
resource "google_storage_bucket" "deployment_artifacts" {
  depends_on = [google_project_service.required_apis]
  
  name          = local.bucket_name
  location      = var.region
  force_destroy = true
  
  # Enable versioning for artifact tracking
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
}

# Create service account for Cloud Deploy
resource "google_service_account" "clouddeploy_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  account_id   = "${var.name_prefix}-clouddeploy-sa-${local.suffix}"
  display_name = "Cloud Deploy Service Account"
  description  = "Service account for Cloud Deploy operations"
}

# Grant necessary permissions to Cloud Deploy service account
resource "google_project_iam_member" "clouddeploy_sa_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/clouddeploy.operator",
    "roles/container.developer",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.editor"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.clouddeploy_sa[0].email}"
}

# Create service account for Cloud Build
resource "google_service_account" "cloudbuild_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  account_id   = "${var.name_prefix}-cloudbuild-sa-${local.suffix}"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations"
}

# Grant necessary permissions to Cloud Build service account
resource "google_project_iam_member" "cloudbuild_sa_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/cloudbuild.builds.editor",
    "roles/clouddeploy.releaser",
    "roles/artifactregistry.writer",
    "roles/storage.objectAdmin",
    "roles/container.developer",
    "roles/logging.logWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa[0].email}"
}

# Development GKE Cluster
resource "google_container_cluster" "dev_cluster" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.cluster_dev_name
  location = var.zone
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Enable features
  enable_shielded_nodes = true
  
  # Workload Identity
  workload_identity_config {
    workload_pool = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
  }
  
  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }
  
  # Monitoring and logging
  logging_config {
    enable_components = var.enable_cloud_logging ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : []
  }
  
  monitoring_config {
    enable_components = var.enable_cloud_monitoring ? ["SYSTEM_COMPONENTS"] : []
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, var.environment_labels.dev)
}

# Development node pool
resource "google_container_node_pool" "dev_nodes" {
  depends_on = [google_container_cluster.dev_cluster]
  
  name       = "${local.cluster_dev_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.dev_cluster.name
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.gke_dev_config.enable_autoscaling ? var.gke_dev_config.min_node_count : null
    max_node_count = var.gke_dev_config.enable_autoscaling ? var.gke_dev_config.max_node_count : null
  }
  
  initial_node_count = var.gke_dev_config.node_count
  
  node_config {
    machine_type = var.gke_dev_config.machine_type
    disk_size_gb = var.gke_dev_config.disk_size_gb
    disk_type    = var.gke_dev_config.disk_type
    preemptible  = var.gke_dev_config.preemptible
    
    # Scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels
    labels = merge(local.common_labels, var.environment_labels.dev)
    
    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = var.gke_dev_config.enable_autorepair
    auto_upgrade = var.gke_dev_config.enable_autoupgrade
  }
  
  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Staging GKE Cluster
resource "google_container_cluster" "staging_cluster" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.cluster_staging_name
  location = var.zone
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Enable features
  enable_shielded_nodes = true
  
  # Workload Identity
  workload_identity_config {
    workload_pool = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
  }
  
  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }
  
  # Monitoring and logging
  logging_config {
    enable_components = var.enable_cloud_logging ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : []
  }
  
  monitoring_config {
    enable_components = var.enable_cloud_monitoring ? ["SYSTEM_COMPONENTS"] : []
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, var.environment_labels.staging)
}

# Staging node pool
resource "google_container_node_pool" "staging_nodes" {
  depends_on = [google_container_cluster.staging_cluster]
  
  name       = "${local.cluster_staging_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.staging_cluster.name
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.gke_staging_config.enable_autoscaling ? var.gke_staging_config.min_node_count : null
    max_node_count = var.gke_staging_config.enable_autoscaling ? var.gke_staging_config.max_node_count : null
  }
  
  initial_node_count = var.gke_staging_config.node_count
  
  node_config {
    machine_type = var.gke_staging_config.machine_type
    disk_size_gb = var.gke_staging_config.disk_size_gb
    disk_type    = var.gke_staging_config.disk_type
    preemptible  = var.gke_staging_config.preemptible
    
    # Scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels
    labels = merge(local.common_labels, var.environment_labels.staging)
    
    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = var.gke_staging_config.enable_autorepair
    auto_upgrade = var.gke_staging_config.enable_autoupgrade
  }
  
  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Production GKE Cluster
resource "google_container_cluster" "prod_cluster" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.cluster_prod_name
  location = var.zone
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Enable features
  enable_shielded_nodes = true
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.gke_prod_config.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.gke_prod_config.enable_private_nodes ? "10.0.0.0/28" : null
  }
  
  # Workload Identity
  workload_identity_config {
    workload_pool = var.enable_workload_identity ? "${var.project_id}.svc.id.goog" : null
  }
  
  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }
  
  # Monitoring and logging
  logging_config {
    enable_components = var.enable_cloud_logging ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : []
  }
  
  monitoring_config {
    enable_components = var.enable_cloud_monitoring ? ["SYSTEM_COMPONENTS"] : []
  }
  
  # Resource labels
  resource_labels = merge(local.common_labels, var.environment_labels.prod)
}

# Production node pool
resource "google_container_node_pool" "prod_nodes" {
  depends_on = [google_container_cluster.prod_cluster]
  
  name       = "${local.cluster_prod_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.prod_cluster.name
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.gke_prod_config.enable_autoscaling ? var.gke_prod_config.min_node_count : null
    max_node_count = var.gke_prod_config.enable_autoscaling ? var.gke_prod_config.max_node_count : null
  }
  
  initial_node_count = var.gke_prod_config.node_count
  
  node_config {
    machine_type = var.gke_prod_config.machine_type
    disk_size_gb = var.gke_prod_config.disk_size_gb
    disk_type    = var.gke_prod_config.disk_type
    preemptible  = var.gke_prod_config.preemptible
    
    # Scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Labels
    labels = merge(local.common_labels, var.environment_labels.prod)
    
    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = var.gke_prod_config.enable_autorepair
    auto_upgrade = var.gke_prod_config.enable_autoupgrade
  }
  
  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "app_pipeline" {
  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.dev_cluster,
    google_container_cluster.staging_cluster,
    google_container_cluster.prod_cluster
  ]
  
  location = var.region
  name     = local.pipeline_name
  
  description = "Multi-environment deployment pipeline for ${var.app_name}"
  
  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.dev_target.name
      profiles  = ["dev"]
    }
    
    stages {
      target_id = google_clouddeploy_target.staging_target.name
      profiles  = ["staging"]
    }
    
    stages {
      target_id = google_clouddeploy_target.prod_target.name
      profiles  = ["prod"]
    }
  }
  
  labels = local.common_labels
}

# Cloud Deploy target for development
resource "google_clouddeploy_target" "dev_target" {
  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.dev_cluster
  ]
  
  location = var.region
  name     = "dev-target"
  
  description = "Development environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.dev_cluster.name}"
  }
  
  labels = merge(local.common_labels, var.environment_labels.dev)
}

# Cloud Deploy target for staging
resource "google_clouddeploy_target" "staging_target" {
  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.staging_cluster
  ]
  
  location = var.region
  name     = "staging-target"
  
  description = "Staging environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.staging_cluster.name}"
  }
  
  require_approval = var.require_approval_for_staging
  
  labels = merge(local.common_labels, var.environment_labels.staging)
}

# Cloud Deploy target for production
resource "google_clouddeploy_target" "prod_target" {
  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.prod_cluster
  ]
  
  location = var.region
  name     = "prod-target"
  
  description = "Production environment target"
  
  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.prod_cluster.name}"
  }
  
  require_approval = var.require_approval_for_prod
  
  labels = merge(local.common_labels, var.environment_labels.prod)
}

# Cloud Build trigger (optional - requires GitHub connection)
resource "google_cloudbuild_trigger" "app_trigger" {
  count = var.github_repo_owner != "" && var.github_repo_name != "" ? 1 : 0
  
  depends_on = [
    google_project_service.required_apis,
    google_clouddeploy_delivery_pipeline.app_pipeline
  ]
  
  name        = "${var.app_name}-trigger-${local.suffix}"
  description = "Trigger for ${var.app_name} deployment pipeline"
  
  github {
    owner = var.github_repo_owner
    name  = var.github_repo_name
    
    push {
      branch = var.branch_pattern
    }
  }
  
  filename = "cloudbuild.yaml"
  
  # Substitutions for build variables
  substitutions = {
    _REGION         = var.region
    _REPO_NAME      = local.repo_name
    _PIPELINE_NAME  = local.pipeline_name
    _BUCKET_NAME    = local.bucket_name
    _APP_NAME       = var.app_name
  }
  
  # Service account
  service_account = var.create_service_accounts ? google_service_account.cloudbuild_sa[0].id : null
  
  tags = ["${var.app_name}", "cloud-deploy", "multi-environment"]
}

# Grant Cloud Build permission to access clusters
resource "google_project_iam_member" "cloudbuild_cluster_access" {
  for_each = toset([
    "roles/container.clusterViewer",
    "roles/container.developer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Get project data
data "google_project" "project" {
  project_id = var.project_id
}

# Grant storage permissions for artifacts
resource "google_storage_bucket_iam_member" "cloudbuild_storage_access" {
  bucket = google_storage_bucket.deployment_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Grant Cloud Deploy permissions for default service account
resource "google_project_iam_member" "default_sa_clouddeploy" {
  project = var.project_id
  role    = "roles/clouddeploy.operator"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}