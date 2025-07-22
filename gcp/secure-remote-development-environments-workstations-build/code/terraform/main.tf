# Secure Remote Development Environment with Cloud Workstations and Cloud Build
# This configuration creates a complete secure development environment on Google Cloud

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment     = var.environment
    security        = "high"
    managed-by      = "terraform"
    project         = "secure-development"
    creation-date   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Resource name prefix with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  
  # Derived names for resources
  workstation_cluster_name = "dev-cluster-${local.resource_suffix}"
  workstation_config_name  = "secure-dev-config-${local.resource_suffix}"
  build_pool_name         = "private-build-pool-${local.resource_suffix}"
  repo_name               = "secure-app-${local.resource_suffix}"
}

# Enable required Google Cloud APIs for the secure development environment
resource "google_project_service" "required_apis" {
  for_each = toset([
    "workstations.googleapis.com",
    "cloudbuild.googleapis.com",
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling when Terraform is destroyed
  disable_on_destroy = false
}

# Create custom VPC network for secure development environment
resource "google_compute_network" "dev_vpc" {
  name                    = "dev-vpc"
  description             = "Secure development environment VPC"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for Cloud Workstations with private Google access
resource "google_compute_subnetwork" "dev_subnet" {
  name                     = "dev-subnet"
  description              = "Subnet for Cloud Workstations and build pools"
  network                  = google_compute_network.dev_vpc.id
  region                   = var.region
  ip_cidr_range           = var.vpc_cidr_range
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logs for security monitoring
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
  
  depends_on = [google_compute_network.dev_vpc]
}

# Create Cloud Workstations cluster within the secure VPC
resource "google_workstations_workstation_cluster" "dev_cluster" {
  workstation_cluster_id = local.workstation_cluster_name
  location              = var.region
  
  network    = google_compute_network.dev_vpc.id
  subnetwork = google_compute_subnetwork.dev_subnet.id
  
  labels = merge(local.common_labels, {
    component = "workstation-cluster"
  })
  
  # Ensure APIs are enabled before creating the cluster
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.dev_subnet
  ]
}

# Create secure workstation configuration template
resource "google_workstations_workstation_config" "secure_config" {
  workstation_config_id   = local.workstation_config_name
  workstation_cluster_id  = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
  location               = var.region
  
  # Host configuration for workstation VMs
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb          = var.workstation_disk_size_gb
      disable_public_ip_addresses = var.disable_public_ip
      
      # Use preemptible instances for cost optimization if enabled
      dynamic "shielded_instance_config" {
        for_each = var.workstation_preemptible ? [] : [1]
        content {
          enable_secure_boot          = true
          enable_vtpm                = true
          enable_integrity_monitoring = true
        }
      }
      
      # Service account for workstation operations
      service_account = google_service_account.workstation_sa.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
  
  # Container configuration for development environment
  container {
    image = var.workstation_container_image
    
    # Environment variables for development setup
    env = {
      WORKSTATION_PROJECT = var.project_id
      WORKSTATION_REGION  = var.region
      REPO_URL           = google_sourcerepo_repository.app_repo.url
    }
    
    # Working directory for development
    working_dir = "/workspace"
    
    # Run container as non-root user for security
    run_as_user = 1000
  }
  
  # Persistent disk configuration
  persistent_directories {
    mount_path = "/home"
    
    gce_pd {
      size_gb        = var.workstation_disk_size_gb
      fs_type        = "ext4"
      disk_type      = var.workstation_disk_type
      reclaim_policy = "DELETE"
    }
  }
  
  # Timeout and lifecycle configuration
  idle_timeout    = "${var.workstation_idle_timeout}s"
  running_timeout = var.workstation_running_timeout
  
  # Security and monitoring configuration
  enable_audit_agent = var.enable_audit_logs
  
  labels = merge(local.common_labels, {
    component = "workstation-config"
    team      = "development"
  })
  
  depends_on = [google_workstations_workstation_cluster.dev_cluster]
}

# Create Cloud Source Repository for secure code storage
resource "google_sourcerepo_repository" "app_repo" {
  name    = local.repo_name
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_registry" {
  repository_id = "${local.repo_name}-images"
  location      = var.region
  format        = "DOCKER"
  description   = "Secure container registry for development applications"
  
  labels = merge(local.common_labels, {
    component = "artifact-registry"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for workstation operations
resource "google_service_account" "workstation_sa" {
  account_id   = "workstation-dev-sa"
  display_name = "Workstation Development Service Account"
  description  = "Service account for secure development workstations"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM permissions to workstation service account
resource "google_project_iam_member" "workstation_source_developer" {
  project = var.project_id
  role    = "roles/source.developer"
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

resource "google_project_iam_member" "workstation_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

resource "google_project_iam_member" "workstation_build_viewer" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.viewer"
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

# Grant workstation access to developer users
resource "google_project_iam_member" "developer_workstation_access" {
  for_each = toset(var.developer_emails)
  
  project = var.project_id
  role    = "roles/workstations.user"
  member  = "user:${each.value}"
}

# Grant workstation access to developer groups
resource "google_project_iam_member" "developer_group_workstation_access" {
  for_each = toset(var.developer_groups)
  
  project = var.project_id
  role    = "roles/workstations.user"
  member  = "group:${each.value}"
}

# Create private Cloud Build worker pool
resource "google_cloudbuild_worker_pool" "private_pool" {
  name     = local.build_pool_name
  location = var.region
  
  worker_config {
    disk_size_gb   = var.build_pool_disk_size_gb
    machine_type   = var.build_pool_machine_type
    no_external_ip = true
  }
  
  network_config {
    peered_network          = google_compute_network.dev_vpc.id
    peered_network_ip_range = var.build_pool_cidr_range
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_network.dev_vpc
  ]
}

# Create Cloud Build trigger for automated builds
resource "google_cloudbuild_trigger" "app_trigger" {
  name        = "secure-dev-trigger-${local.resource_suffix}"
  description = "Automated secure build trigger for ${local.repo_name}"
  location    = var.region
  
  # Service account for build operations
  service_account = google_service_account.build_sa.id
  
  # Source repository configuration
  source_to_build {
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
    
    repo_source {
      project_id   = var.project_id
      repo_name    = google_sourcerepo_repository.app_repo.name
      branch_name  = var.source_repo_branch_pattern
    }
  }
  
  # Build configuration
  git_file_source {
    path      = var.cloudbuild_filename
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
    revision {
      branch_name = var.source_repo_branch_pattern
    }
  }
  
  # Use private worker pool for secure builds
  build {
    options {
      worker_pool = google_cloudbuild_worker_pool.private_pool.id
      logging     = "CLOUD_LOGGING_ONLY"
    }
    
    # Default build steps if no cloudbuild.yaml exists
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/app:$BUILD_ID",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/app:$BUILD_ID"
      ]
    }
    
    images = [
      "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/app:$BUILD_ID"
    ]
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_sourcerepo_repository.app_repo,
    google_cloudbuild_worker_pool.private_pool
  ]
}

# Create service account for Cloud Build operations
resource "google_service_account" "build_sa" {
  account_id   = "cloudbuild-secure-sa"
  display_name = "Cloud Build Secure Service Account"
  description  = "Service account for secure Cloud Build operations"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Build service account necessary permissions
resource "google_project_iam_member" "build_sa_cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.build_sa.email}"
}

resource "google_project_iam_member" "build_sa_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build_sa.email}"
}

resource "google_project_iam_member" "build_sa_source_reader" {
  project = var.project_id
  role    = "roles/source.reader"
  member  = "serviceAccount:${google_service_account.build_sa.email}"
}

# Create development workstation instance
resource "google_workstations_workstation" "dev_workstation" {
  workstation_id         = "dev-workstation-01"
  workstation_config_id  = google_workstations_workstation_config.secure_config.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.dev_cluster.workstation_cluster_id
  location              = var.region
  
  labels = merge(local.common_labels, {
    component = "workstation-instance"
    developer = "team-lead"
    usage     = "development"
  })
  
  depends_on = [google_workstations_workstation_config.secure_config]
}