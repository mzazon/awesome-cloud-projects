# Multi-Environment Testing Pipelines with Google Cloud Infrastructure Manager
# This configuration deploys a complete CI/CD pipeline with multiple GKE environments,
# Cloud Deploy for progressive delivery, and comprehensive monitoring.

terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# Variables for customization
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The Google Cloud zone for GKE clusters"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "pipeline"
}

variable "machine_type_dev" {
  description = "Machine type for development cluster nodes"
  type        = string
  default     = "e2-medium"
}

variable "machine_type_staging" {
  description = "Machine type for staging cluster nodes"
  type        = string
  default     = "e2-medium"
}

variable "machine_type_prod" {
  description = "Machine type for production cluster nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count_dev" {
  description = "Number of nodes in development cluster"
  type        = number
  default     = 2
}

variable "node_count_staging" {
  description = "Number of nodes in staging cluster"
  type        = number
  default     = 2
}

variable "node_count_prod" {
  description = "Number of nodes in production cluster"
  type        = number
  default     = 3
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  cluster_prefix    = "${var.cluster_prefix}-${random_id.suffix.hex}"
  repository_name   = "${local.cluster_prefix}-repo"
  pipeline_name     = "${local.cluster_prefix}-pipeline"
  dev_cluster_name  = "${local.cluster_prefix}-dev"
  staging_cluster_name = "${local.cluster_prefix}-staging"
  prod_cluster_name = "${local.cluster_prefix}-prod"
  
  # Common labels for all resources
  common_labels = {
    environment = "multi-env-pipeline"
    managed-by  = "infrastructure-manager"
    project     = "testing-pipeline"
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  disable_on_destroy = false
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_repo" {
  provider = google-beta
  
  location      = var.region
  project       = var.project_id
  repository_id = local.repository_name
  description   = "Container repository for multi-environment pipeline"
  format        = "DOCKER"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Build
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "${local.cluster_prefix}-build-sa"
  display_name = "Cloud Build Service Account for Pipeline"
  description  = "Service account used by Cloud Build for the testing pipeline"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Deploy
resource "google_service_account" "clouddeploy_sa" {
  account_id   = "${local.cluster_prefix}-deploy-sa"
  display_name = "Cloud Deploy Service Account for Pipeline"
  description  = "Service account used by Cloud Deploy for the testing pipeline"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for Cloud Build Service Account
resource "google_project_iam_member" "cloudbuild_permissions" {
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
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# IAM bindings for Cloud Deploy Service Account
resource "google_project_iam_member" "clouddeploy_permissions" {
  for_each = toset([
    "roles/clouddeploy.operator",
    "roles/container.clusterAdmin",
    "roles/artifactregistry.reader",
    "roles/storage.admin",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.clouddeploy_sa.email}"
}

# Development GKE Cluster
resource "google_container_cluster" "dev_cluster" {
  name     = local.dev_cluster_name
  location = var.zone
  project  = var.project_id

  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network and security configuration
  network    = "default"
  subnetwork = "default"

  # Enable important features
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  # Workload Identity for secure service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Cluster monitoring configuration
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
    managed_prometheus {
      enabled = true
    }
  }

  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "development"
  })

  depends_on = [google_project_service.required_apis]
}

# Development cluster node pool
resource "google_container_node_pool" "dev_nodes" {
  name       = "${local.dev_cluster_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.dev_cluster.name
  node_count = var.node_count_dev
  project    = var.project_id

  node_config {
    preemptible  = false
    machine_type = var.machine_type_dev
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Google recommends custom service accounts with minimal permissions
    service_account = google_service_account.cloudbuild_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security settings
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(local.common_labels, {
      environment = "development"
    })
  }

  # Auto-repair and auto-upgrade
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Staging GKE Cluster
resource "google_container_cluster" "staging_cluster" {
  name     = local.staging_cluster_name
  location = var.zone
  project  = var.project_id

  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network and security configuration
  network    = "default"
  subnetwork = "default"

  # Enable important features
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  # Workload Identity for secure service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Cluster monitoring configuration
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
    managed_prometheus {
      enabled = true
    }
  }

  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "staging"
  })

  depends_on = [google_project_service.required_apis]
}

# Staging cluster node pool
resource "google_container_node_pool" "staging_nodes" {
  name       = "${local.staging_cluster_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.staging_cluster.name
  node_count = var.node_count_staging
  project    = var.project_id

  node_config {
    preemptible  = false
    machine_type = var.machine_type_staging
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Google recommends custom service accounts with minimal permissions
    service_account = google_service_account.cloudbuild_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Security settings
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(local.common_labels, {
      environment = "staging"
    })
  }

  # Auto-repair and auto-upgrade
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Production GKE Cluster
resource "google_container_cluster" "prod_cluster" {
  name     = local.prod_cluster_name
  location = var.zone
  project  = var.project_id

  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network and security configuration
  network    = "default"
  subnetwork = "default"

  # Enable important features for production
  enable_shielded_nodes = true
  enable_legacy_abac    = false
  enable_network_policy = true

  # Workload Identity for secure service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enhanced cluster monitoring for production
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER"
    ]
    managed_prometheus {
      enabled = true
    }
  }

  # Binary Authorization for enhanced security
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "production"
  })

  depends_on = [google_project_service.required_apis]
}

# Production cluster node pool
resource "google_container_node_pool" "prod_nodes" {
  name       = "${local.prod_cluster_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.prod_cluster.name
  node_count = var.node_count_prod
  project    = var.project_id

  node_config {
    preemptible  = false
    machine_type = var.machine_type_prod
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    # Google recommends custom service accounts with minimal permissions
    service_account = google_service_account.cloudbuild_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Enhanced security settings for production
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(local.common_labels, {
      environment = "production"
    })
  }

  # Auto-repair and auto-upgrade
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Cloud Deploy Delivery Pipeline
resource "google_clouddeploy_delivery_pipeline" "pipeline" {
  provider = google-beta
  
  name        = local.pipeline_name
  location    = var.region
  description = "Multi-environment testing pipeline for progressive delivery"
  project     = var.project_id

  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.dev_target.name
      profiles  = ["dev"]
      strategy {
        standard {
          verify = true
        }
      }
    }

    stages {
      target_id = google_clouddeploy_target.staging_target.name
      profiles  = ["staging"]
      strategy {
        standard {
          verify = true
        }
      }
    }

    stages {
      target_id = google_clouddeploy_target.prod_target.name
      profiles  = ["prod"]
      strategy {
        standard {
          verify = true
        }
      }
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.dev_cluster,
    google_container_cluster.staging_cluster,
    google_container_cluster.prod_cluster
  ]
}

# Cloud Deploy Target for Development
resource "google_clouddeploy_target" "dev_target" {
  provider = google-beta
  
  name        = "dev"
  location    = var.region
  description = "Development environment target"
  project     = var.project_id

  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${local.dev_cluster_name}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.clouddeploy_sa.email
    artifact_storage  = "gs://${google_storage_bucket.deployment_artifacts.name}/dev"
  }

  labels = merge(local.common_labels, {
    environment = "development"
  })

  depends_on = [google_container_cluster.dev_cluster]
}

# Cloud Deploy Target for Staging
resource "google_clouddeploy_target" "staging_target" {
  provider = google-beta
  
  name        = "staging"
  location    = var.region
  description = "Staging environment target"
  project     = var.project_id

  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${local.staging_cluster_name}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.clouddeploy_sa.email
    artifact_storage  = "gs://${google_storage_bucket.deployment_artifacts.name}/staging"
  }

  labels = merge(local.common_labels, {
    environment = "staging"
  })

  depends_on = [google_container_cluster.staging_cluster]
}

# Cloud Deploy Target for Production
resource "google_clouddeploy_target" "prod_target" {
  provider = google-beta
  
  name        = "prod"
  location    = var.region
  description = "Production environment target"
  project     = var.project_id

  require_approval = true

  gke {
    cluster = "projects/${var.project_id}/locations/${var.zone}/clusters/${local.prod_cluster_name}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.clouddeploy_sa.email
    artifact_storage  = "gs://${google_storage_bucket.deployment_artifacts.name}/prod"
  }

  labels = merge(local.common_labels, {
    environment = "production"
  })

  depends_on = [google_container_cluster.prod_cluster]
}

# Cloud Storage bucket for deployment artifacts
resource "google_storage_bucket" "deployment_artifacts" {
  name     = "${local.cluster_prefix}-deploy-artifacts"
  location = var.region
  project  = var.project_id

  # Enable versioning for artifact history
  versioning {
    enabled = true
  }

  # Security settings
  uniform_bucket_level_access = true
  
  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for Cloud Build logs
resource "google_storage_bucket" "build_logs" {
  name     = "${local.cluster_prefix}-build-logs"
  location = var.region
  project  = var.project_id

  # Security settings
  uniform_bucket_level_access = true
  
  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Build Trigger for automated builds (optional, can be configured manually)
resource "google_cloudbuild_trigger" "pipeline_trigger" {
  provider = google-beta
  
  name        = "${local.cluster_prefix}-build-trigger"
  description = "Trigger for multi-environment testing pipeline"
  project     = var.project_id

  # Trigger on main branch commits (adjust as needed)
  github {
    owner = "your-github-username"  # Replace with actual GitHub username
    name  = "your-repo-name"        # Replace with actual repository name
    push {
      branch = "^main$"
    }
  }

  # Build configuration
  build {
    # Build steps configuration
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/sample-app:$BUILD_ID",
        "."
      ]
    }

    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/sample-app:$BUILD_ID"
      ]
    }

    step {
      name       = "gcr.io/cloud-builders/gcloud"
      entrypoint = "bash"
      args = [
        "-c",
        "gcloud deploy releases create release-$BUILD_ID --delivery-pipeline=${local.pipeline_name} --region=${var.region} --images=sample-app=${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/sample-app:$BUILD_ID"
      ]
    }

    # Use custom service account
    options {
      logging = "CLOUD_LOGGING_ONLY"
      log_streaming_option = "STREAM_ON"
      substitution_option  = "ALLOW_LOOSE"
    }

    substitutions = {
      _ARTIFACT_REGISTRY_REPO = local.repository_name
      _PIPELINE_NAME         = local.pipeline_name
    }
  }

  service_account = google_service_account.cloudbuild_sa.id

  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.container_repo,
    google_clouddeploy_delivery_pipeline.pipeline
  ]
}

# Cloud Monitoring Dashboard for pipeline observability
resource "google_monitoring_dashboard" "pipeline_dashboard" {
  dashboard_json = jsonencode({
    displayName = "${local.cluster_prefix} Pipeline Dashboard"
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
                      filter = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=~\"${local.cluster_prefix}.*\""
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
                  filter = "resource.type=\"clouddeploy_delivery_pipeline\" AND resource.labels.pipeline_id=\"${local.pipeline_name}\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_COUNT"
                  }
                }
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Cloud Build Job Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"build\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_RATE"
                        crossSeriesReducer  = "REDUCE_COUNT"
                        groupByFields       = ["metric.labels.status"]
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

  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Output values for reference
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "cluster_prefix" {
  description = "The prefix used for resource names"
  value       = local.cluster_prefix
}

output "artifact_registry_repository" {
  description = "The Artifact Registry repository for container images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}"
}

output "dev_cluster_name" {
  description = "Name of the development GKE cluster"
  value       = google_container_cluster.dev_cluster.name
}

output "staging_cluster_name" {
  description = "Name of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.name
}

output "prod_cluster_name" {
  description = "Name of the production GKE cluster"
  value       = google_container_cluster.prod_cluster.name
}

output "delivery_pipeline_name" {
  description = "Name of the Cloud Deploy delivery pipeline"
  value       = google_clouddeploy_delivery_pipeline.pipeline.name
}

output "cloudbuild_service_account" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloudbuild_sa.email
}

output "clouddeploy_service_account" {
  description = "Email of the Cloud Deploy service account"
  value       = google_service_account.clouddeploy_sa.email
}

output "deployment_artifacts_bucket" {
  description = "Name of the Cloud Storage bucket for deployment artifacts"
  value       = google_storage_bucket.deployment_artifacts.name
}

output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.pipeline_dashboard.id}?project=${var.project_id}"
}

output "connect_to_dev_cluster" {
  description = "Command to connect to the development cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.dev_cluster.name} --zone ${var.zone} --project ${var.project_id}"
}

output "connect_to_staging_cluster" {
  description = "Command to connect to the staging cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.staging_cluster.name} --zone ${var.zone} --project ${var.project_id}"
}

output "connect_to_prod_cluster" {
  description = "Command to connect to the production cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.prod_cluster.name} --zone ${var.zone} --project ${var.project_id}"
}