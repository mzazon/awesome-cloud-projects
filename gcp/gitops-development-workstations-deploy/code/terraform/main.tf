# GitOps Development Workflow Infrastructure
# This configuration creates a complete GitOps development environment with:
# - GKE clusters for staging and production
# - Cloud Workstations for development environments
# - Cloud Source Repositories for version control
# - Artifact Registry for container images
# - Cloud Build for CI/CD pipelines
# - Cloud Deploy for progressive delivery

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Generate unique names using random suffix
  cluster_staging_name     = "${var.cluster_name_prefix}-staging-${random_id.suffix.hex}"
  cluster_production_name  = "${var.cluster_name_prefix}-prod-${random_id.suffix.hex}"
  workstation_cluster_name = "${var.workstation_config_prefix}-cluster-${random_id.suffix.hex}"
  workstation_config_name  = "${var.workstation_config_prefix}-${random_id.suffix.hex}"
  app_repo_final_name      = "${var.app_repo_name}-${random_id.suffix.hex}"
  env_repo_final_name      = "${var.env_repo_name}-${random_id.suffix.hex}"
  artifact_repo_name       = "${var.artifact_registry_repo_name}-${random_id.suffix.hex}"
  
  # Network configuration
  network_name    = var.create_custom_network ? google_compute_network.gitops_network[0].name : var.network_name
  subnet_name     = var.create_custom_network ? google_compute_subnetwork.gitops_subnet[0].name : var.subnet_name
  network_self_link = var.create_custom_network ? google_compute_network.gitops_network[0].self_link : "projects/${var.project_id}/global/networks/${var.network_name}"
  subnet_self_link  = var.create_custom_network ? google_compute_subnetwork.gitops_subnet[0].self_link : "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.subnet_name}"
  
  # Common labels applied to all resources
  common_labels = merge(var.environment_labels, {
    terraform_managed = "true"
    recipe_id        = "f3a8b2c4"
    recipe_name      = "gitops-development-workstations-deploy"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling when resource is destroyed
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create custom VPC network (optional)
resource "google_compute_network" "gitops_network" {
  count = var.create_custom_network ? 1 : 0
  
  name                    = "gitops-network-${random_id.suffix.hex}"
  description             = "Custom VPC network for GitOps development workflow"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.required_apis]
}

# Create custom subnet (optional)
resource "google_compute_subnetwork" "gitops_subnet" {
  count = var.create_custom_network ? 1 : 0
  
  name          = "gitops-subnet-${random_id.suffix.hex}"
  description   = "Subnet for GitOps development workflow resources"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.gitops_network[0].id
  
  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pod-range"
    ip_cidr_range = var.pod_cidr
  }
  
  secondary_ip_range {
    range_name    = "service-range"
    ip_cidr_range = var.service_cidr
  }
  
  depends_on = [google_compute_network.gitops_network]
}

# Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_repo" {
  repository_id = local.artifact_repo_name
  location      = var.region
  format        = "DOCKER"
  description   = "Container registry for GitOps application images"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Source Repository for application code
resource "google_sourcerepo_repository" "app_repo" {
  name = local.app_repo_final_name
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Source Repository for environment configurations
resource "google_sourcerepo_repository" "env_repo" {
  name = local.env_repo_final_name
  
  depends_on = [google_project_service.required_apis]
}

# GKE Staging Cluster
resource "google_container_cluster" "staging" {
  name     = local.cluster_staging_name
  location = var.region
  
  # Use Autopilot mode for simplified cluster management
  enable_autopilot = var.gke_autopilot_enabled
  
  # Network configuration
  network    = local.network_self_link
  subnetwork = local.subnet_self_link
  
  # Cluster configuration
  description = "GKE staging cluster for GitOps development workflow"
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "staging"
    cluster_type = "staging"
  })
  
  # Security and identity configuration
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy && !var.gke_autopilot_enabled ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Binary Authorization configuration
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }
  
  # IP allocation for custom network
  dynamic "ip_allocation_policy" {
    for_each = var.create_custom_network ? [1] : []
    content {
      cluster_secondary_range_name  = "pod-range"
      services_secondary_range_name = "service-range"
    }
  }
  
  # Node configuration (only for standard GKE)
  dynamic "node_config" {
    for_each = var.gke_autopilot_enabled ? [] : [1]
    content {
      machine_type = var.gke_node_machine_type
      oauth_scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
        "https://www.googleapis.com/auth/servicecontrol",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/trace.append"
      ]
      
      labels = merge(local.common_labels, {
        node_pool = "default"
      })
      
      # Enable Workload Identity
      workload_metadata_config {
        mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
      }
    }
  }
  
  # Initial node count (only for standard GKE)
  dynamic "initial_node_count" {
    for_each = var.gke_autopilot_enabled ? [] : [1]
    content {
      value = var.gke_node_count
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.gitops_subnet
  ]
}

# GKE Production Cluster
resource "google_container_cluster" "production" {
  name     = local.cluster_production_name
  location = var.region
  
  # Use Autopilot mode for simplified cluster management
  enable_autopilot = var.gke_autopilot_enabled
  
  # Network configuration
  network    = local.network_self_link
  subnetwork = local.subnet_self_link
  
  # Cluster configuration
  description = "GKE production cluster for GitOps development workflow"
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "production"
    cluster_type = "production"
  })
  
  # Security and identity configuration
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy && !var.gke_autopilot_enabled ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Binary Authorization configuration
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }
  
  # IP allocation for custom network
  dynamic "ip_allocation_policy" {
    for_each = var.create_custom_network ? [1] : []
    content {
      cluster_secondary_range_name  = "pod-range"
      services_secondary_range_name = "service-range"
    }
  }
  
  # Node configuration (only for standard GKE)
  dynamic "node_config" {
    for_each = var.gke_autopilot_enabled ? [] : [1]
    content {
      machine_type = var.gke_node_machine_type
      oauth_scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
        "https://www.googleapis.com/auth/servicecontrol",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/trace.append"
      ]
      
      labels = merge(local.common_labels, {
        node_pool = "default"
      })
      
      # Enable Workload Identity
      workload_metadata_config {
        mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
      }
    }
  }
  
  # Initial node count (only for standard GKE)
  dynamic "initial_node_count" {
    for_each = var.gke_autopilot_enabled ? [] : [1]
    content {
      value = var.gke_node_count
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.gitops_subnet
  ]
}

# Cloud Workstations cluster
resource "google_workstations_workstation_cluster" "dev_cluster" {
  provider = google-beta
  
  workstation_cluster_id = local.workstation_cluster_name
  location               = var.region
  
  # Network configuration
  network    = local.network_self_link
  subnetwork = local.subnet_self_link
  
  # Labels for organization
  labels = merge(local.common_labels, {
    workstation_cluster = "development"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.gitops_subnet
  ]
}

# Wait for workstation cluster to be ready
resource "time_sleep" "wait_for_workstation_cluster" {
  depends_on = [google_workstations_workstation_cluster.dev_cluster]
  
  create_duration = "60s"
}

# Cloud Workstations configuration
resource "google_workstations_workstation_config" "dev_config" {
  provider = google-beta
  
  workstation_config_id          = local.workstation_config_name
  workstation_cluster_id         = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
  location                       = var.region
  
  # Machine configuration
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb          = var.workstation_disk_size_gb
      disable_public_ip_addresses = false
    }
  }
  
  # Container configuration
  container {
    image = var.workstation_container_image
    
    # Environment variables for development
    env = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
  }
  
  # Persistent directories
  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb        = var.workstation_disk_size_gb
      fs_type        = "ext4"
      disk_type      = "pd-standard"
      reclaim_policy = "DELETE"
    }
  }
  
  # Labels for organization
  labels = merge(local.common_labels, {
    workstation_config = "development"
  })
  
  depends_on = [time_sleep.wait_for_workstation_cluster]
}

# Cloud Workstation instance
resource "google_workstations_workstation" "dev_workstation" {
  provider = google-beta
  
  workstation_id         = "dev-workstation"
  workstation_config_id  = google_workstations_workstation_config.dev_config.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
  location               = var.region
  
  # Labels for organization
  labels = merge(local.common_labels, {
    workstation_instance = "development"
  })
  
  depends_on = [google_workstations_workstation_config.dev_config]
}

# Service account for Cloud Build
resource "google_service_account" "cloudbuild" {
  account_id   = "gitops-cloudbuild-${random_id.suffix.hex}"
  display_name = "Cloud Build Service Account for GitOps Pipeline"
  description  = "Service account used by Cloud Build for GitOps CI/CD operations"
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/source.admin",
    "roles/artifactregistry.writer",
    "roles/container.developer",
    "roles/clouddeploy.developer",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
  
  depends_on = [google_service_account.cloudbuild]
}

# Cloud Build trigger for application repository
resource "google_cloudbuild_trigger" "app_trigger" {
  name        = "gitops-app-trigger-${random_id.suffix.hex}"
  description = "Trigger for GitOps application code changes"
  location    = var.region
  
  # Repository configuration
  source_to_build {
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
    uri       = google_sourcerepo_repository.app_repo.url
    ref       = "refs/heads/main"
  }
  
  # Build configuration
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.artifact_repo_name}/hello-app:$SHORT_SHA",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.artifact_repo_name}/hello-app:$SHORT_SHA"
      ]
    }
    
    step {
      name       = "gcr.io/cloud-builders/gcloud"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        gcloud source repos clone ${local.env_repo_final_name} env-repo
        cd env-repo
        git config user.email "cloudbuild@${var.project_id}.iam.gserviceaccount.com"
        git config user.name "Cloud Build"
        
        # Update the deployment manifest
        sed -i "s|image: .*|image: ${var.region}-docker.pkg.dev/${var.project_id}/${local.artifact_repo_name}/hello-app:$SHORT_SHA|g" k8s/hello-app-deployment.yaml
        git add .
        git commit -m "Update image to $SHORT_SHA" || exit 0
        git push origin main
        EOT
      ]
    }
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    
    substitutions = {
      _REGION     = var.region
      _APP_REPO   = local.artifact_repo_name
      _ENV_REPO   = local.env_repo_final_name
    }
  }
  
  # Service account for builds
  service_account = google_service_account.cloudbuild.id
  
  depends_on = [
    google_sourcerepo_repository.app_repo,
    google_sourcerepo_repository.env_repo,
    google_artifact_registry_repository.container_repo,
    google_service_account.cloudbuild,
    google_project_iam_member.cloudbuild_roles
  ]
}

# Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "gitops_pipeline" {
  location = var.region
  name     = var.cloud_deploy_pipeline_name
  
  description = "GitOps delivery pipeline for progressive deployment"
  
  # Pipeline stages
  serial_pipeline {
    stage {
      target_id = google_clouddeploy_target.staging.name
      profiles  = []
    }
    
    stage {
      target_id = google_clouddeploy_target.production.name
      profiles  = []
      
      strategy {
        standard {
          verify = false
        }
      }
    }
  }
  
  # Labels for organization
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Deploy target for staging environment
resource "google_clouddeploy_target" "staging" {
  location = var.region
  name     = "staging"
  
  description = "Staging environment target for GitOps deployments"
  
  # GKE cluster configuration
  gke {
    cluster = google_container_cluster.staging.id
  }
  
  # Labels for organization
  labels = merge(local.common_labels, {
    environment = "staging"
  })
  
  depends_on = [
    google_container_cluster.staging,
    google_project_service.required_apis
  ]
}

# Cloud Deploy target for production environment
resource "google_clouddeploy_target" "production" {
  location = var.region
  name     = "production"
  
  description = "Production environment target for GitOps deployments"
  
  # GKE cluster configuration
  gke {
    cluster = google_container_cluster.production.id
  }
  
  # Labels for organization
  labels = merge(local.common_labels, {
    environment = "production"
  })
  
  depends_on = [
    google_container_cluster.production,
    google_project_service.required_apis
  ]
}