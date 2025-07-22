# main.tf - Main configuration for multi-environment application deployment
# This file creates the complete infrastructure for Cloud Deploy and Cloud Build CI/CD pipeline

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels for all resources
  common_labels = merge(var.labels, {
    project = var.project_id
    region  = var.region
  })
  
  # Resource names with random suffix
  cluster_prefix = "${var.cluster_prefix}-${random_id.suffix.hex}"
  bucket_name    = "${var.project_id}-build-artifacts-${random_id.suffix.hex}"
  
  # Environment configurations
  environments = ["dev", "staging", "prod"]
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Don't disable the service on destroy to avoid issues
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create Cloud Storage bucket for build artifacts
resource "google_storage_bucket" "build_artifacts" {
  name          = local.bucket_name
  location      = var.storage_location
  force_destroy = !var.enable_deletion_protection
  
  # Enable versioning for build artifacts
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
  
  depends_on = [google_project_service.required_apis]
}

# Create GKE Autopilot clusters for each environment
resource "google_container_cluster" "environment_clusters" {
  for_each = toset(local.environments)
  
  name     = "${local.cluster_prefix}-${each.value}"
  location = var.region
  
  # Enable Autopilot mode for simplified cluster management
  enable_autopilot = var.gke_autopilot_enabled
  
  # Release channel for automatic updates
  release_channel {
    channel = var.gke_release_channel
  }
  
  # Security and monitoring configurations
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    
    managed_prometheus {
      enabled = true
    }
  }
  
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  # Network policy for security
  network_policy {
    enabled = true
  }
  
  # Deletion protection for production
  deletion_protection = each.value == "prod" ? var.enable_deletion_protection : false
  
  # Labels for resource management
  resource_labels = merge(local.common_labels, {
    environment = each.value
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Deploy
resource "google_service_account" "clouddeploy_sa" {
  account_id   = "clouddeploy-sa-${random_id.suffix.hex}"
  display_name = "Cloud Deploy Service Account"
  description  = "Service account for Cloud Deploy operations across environments"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to Cloud Deploy service account
resource "google_project_iam_member" "clouddeploy_sa_permissions" {
  for_each = toset([
    "roles/container.clusterAdmin",
    "roles/clouddeploy.jobRunner",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/storage.objectViewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.clouddeploy_sa.email}"
}

# Create Cloud Deploy targets for each environment
resource "google_clouddeploy_target" "environment_targets" {
  for_each = toset(local.environments)
  
  location = var.region
  name     = "${each.value}-target"
  
  description = "Cloud Deploy target for ${each.value} environment"
  
  gke {
    cluster = google_container_cluster.environment_clusters[each.value].id
  }
  
  execution_configs {
    usages = ["RENDER", "DEPLOY"]
    
    default_pool {
      service_account = google_service_account.clouddeploy_sa.email
    }
  }
  
  # Require approval for staging and production
  require_approval = var.environments[each.value].require_approval
  
  labels = merge(local.common_labels, {
    environment = each.value
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.clouddeploy_sa_permissions
  ]
}

# Create Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "main_pipeline" {
  location = var.region
  name     = var.pipeline_name
  
  description = "Multi-environment deployment pipeline for ${var.app_name}"
  
  serial_pipeline {
    # Development stage
    stages {
      target_id = google_clouddeploy_target.environment_targets["dev"].name
      profiles  = []
      
      strategy {
        standard {
          verify = var.environments.dev.verify_deployment
        }
      }
    }
    
    # Staging stage
    stages {
      target_id = google_clouddeploy_target.environment_targets["staging"].name
      profiles  = []
      
      strategy {
        standard {
          verify = var.environments.staging.verify_deployment
        }
      }
    }
    
    # Production stage with canary deployment
    stages {
      target_id = google_clouddeploy_target.environment_targets["prod"].name
      profiles  = []
      
      strategy {
        canary {
          runtime_config {
            kubernetes {
              service_networking {
                service    = "prod-${var.app_name}-service"
                deployment = "prod-${var.app_name}"
              }
            }
          }
          
          canary_deployment {
            percentages = var.environments.prod.canary_percentages
            verify      = var.environments.prod.verify_deployment
          }
        }
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_clouddeploy_target.environment_targets
  ]
}

# Create Cloud Build service account with enhanced permissions
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "cloudbuild-sa-${random_id.suffix.hex}"
  display_name = "Cloud Build Service Account"
  description  = "Enhanced service account for Cloud Build operations"
  
  depends_on = [google_project_service.required_apis]
}

# Grant permissions to Cloud Build service account
resource "google_project_iam_member" "cloudbuild_sa_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/clouddeploy.releaser",
    "roles/container.admin",
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/secretmanager.accessor"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Create Cloud Build trigger (manual trigger for demonstration)
resource "google_cloudbuild_trigger" "main_trigger" {
  name        = "${var.app_name}-trigger"
  description = "Trigger for ${var.app_name} CI/CD pipeline"
  
  # Manual trigger configuration
  manual_trigger {}
  
  # Build configuration
  build {
    timeout = var.cloud_build_timeout
    
    options {
      logging         = "CLOUD_LOGGING_ONLY"
      machine_type    = var.cloud_build_machine_type
      substitution_option = "ALLOW_LOOSE"
    }
    
    # Build the container image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${var.project_id}/${var.app_name}:$SHORT_SHA",
        "."
      ]
    }
    
    # Push the image to Container Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${var.project_id}/${var.app_name}:$SHORT_SHA"
      ]
    }
    
    # Prepare manifests using gke-deploy
    step {
      name = "gcr.io/cloud-builders/gke-deploy"
      args = [
        "prepare",
        "--filename=k8s/overlays/dev",
        "--image=gcr.io/${var.project_id}/${var.app_name}:$SHORT_SHA",
        "--app=${var.app_name}",
        "--version=$SHORT_SHA",
        "--namespace=default",
        "--output=output"
      ]
    }
    
    # Create release in Cloud Deploy
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "deploy", "releases", "create", "release-$SHORT_SHA",
        "--delivery-pipeline=${google_clouddeploy_delivery_pipeline.main_pipeline.name}",
        "--region=${var.region}",
        "--source=output"
      ]
    }
    
    # Specify images to be pushed
    images = ["gcr.io/${var.project_id}/${var.app_name}:$SHORT_SHA"]
    
    # Substitutions for build variables
    substitutions = {
      _APP_NAME       = var.app_name
      _PIPELINE_NAME  = google_clouddeploy_delivery_pipeline.main_pipeline.name
      _REGION         = var.region
      _CLOUDDEPLOY_SA = google_service_account.clouddeploy_sa.email
    }
  }
  
  # Use custom service account
  service_account = google_service_account.cloudbuild_sa.id
  
  tags = ["ci-cd", "multi-environment", var.app_name]
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloudbuild_sa_permissions,
    google_clouddeploy_delivery_pipeline.main_pipeline
  ]
}

# Optional: Create GitHub connection for Cloud Build (if enabled)
resource "google_cloudbuild_trigger" "github_trigger" {
  count = var.create_github_connection && var.github_repository != "" ? 1 : 0
  
  name        = "${var.app_name}-github-trigger"
  description = "GitHub trigger for ${var.app_name} CI/CD pipeline"
  
  # GitHub configuration
  github {
    owner = split("/", var.github_repository)[0]
    name  = split("/", var.github_repository)[1]
    
    push {
      branch = var.github_branch_pattern
    }
  }
  
  # Use the same build configuration as manual trigger
  filename = "cloudbuild.yaml"
  
  # Use custom service account
  service_account = google_service_account.cloudbuild_sa.id
  
  tags = ["ci-cd", "github", "multi-environment", var.app_name]
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cloudbuild_sa_permissions,
    google_clouddeploy_delivery_pipeline.main_pipeline
  ]
}

# Create Cloud Logging sink for deployment logs
resource "google_logging_project_sink" "clouddeploy_logs" {
  name        = "clouddeploy-logs-${random_id.suffix.hex}"
  destination = "storage.googleapis.com/${google_storage_bucket.build_artifacts.name}/logs"
  
  # Filter for Cloud Deploy logs
  filter = "resource.type=\"clouddeploy.googleapis.com/DeliveryPipeline\" OR resource.type=\"clouddeploy.googleapis.com/Target\""
  
  # Create a unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant the logging sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "logs_sink_writer" {
  bucket = google_storage_bucket.build_artifacts.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.clouddeploy_logs.writer_identity
}

# Create monitoring dashboard for deployment metrics
resource "google_monitoring_dashboard" "deployment_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Multi-Environment Deployment Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Deploy Releases"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"clouddeploy.googleapis.com/DeliveryPipeline\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Build Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"build\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
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