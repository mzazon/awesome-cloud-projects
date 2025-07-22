# Enterprise Deployment Pipeline Infrastructure for Google Cloud Platform
# This Terraform configuration creates a complete CI/CD pipeline using Cloud Build, 
# Cloud Deploy, and Service Catalog with GKE clusters for multi-environment deployment

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming with random suffix
  name_suffix = random_id.suffix.hex
  
  # Environment-specific cluster names
  cluster_names = {
    for env in var.environments : env => "${var.cluster_name_prefix}-${env}-${local.name_suffix}"
  }
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    pipeline   = "enterprise-deployment"
  })
  
  # Repository names with suffix
  repository_name = "${var.artifact_repository_name}-${local.name_suffix}"
  pipeline_name   = "${var.pipeline_name}-${local.name_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "servicecatalog.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "sourcerepo.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create GKE Autopilot clusters for each environment
resource "google_container_cluster" "gke_clusters" {
  for_each = var.gke_autopilot_enabled ? local.cluster_names : {}

  name     = each.value
  location = var.region
  project  = var.project_id

  # Enable Autopilot for simplified cluster management
  enable_autopilot = true

  # Network configuration
  network    = "default"
  subnetwork = "default"

  # IP allocation policy for IP aliasing
  dynamic "ip_allocation_policy" {
    for_each = var.enable_ip_alias ? [1] : []
    content {
      cluster_ipv4_cidr_block  = ""
      services_ipv4_cidr_block = ""
    }
  }

  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }

  # Security configuration for production environment
  dynamic "node_config" {
    for_each = each.key == "prod" && var.enable_shielded_nodes ? [1] : []
    content {
      shielded_instance_config {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }
  }

  # Workload Identity configuration
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = each.key
    cluster-type = "autopilot"
  })

  # Deletion protection for production
  deletion_protection = each.key == "prod" ? true : false

  depends_on = [
    google_project_service.required_apis
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create standard GKE clusters if Autopilot is disabled
resource "google_container_cluster" "gke_standard_clusters" {
  for_each = var.gke_autopilot_enabled ? {} : local.cluster_names

  name     = each.value
  location = var.zone
  project  = var.project_id

  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = "default"
  subnetwork = "default"

  # IP allocation policy for IP aliasing
  dynamic "ip_allocation_policy" {
    for_each = var.enable_ip_alias ? [1] : []
    content {
      cluster_ipv4_cidr_block  = ""
      services_ipv4_cidr_block = ""
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

  # Workload Identity configuration
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = each.key
    cluster-type = "standard"
  })

  depends_on = [
    google_project_service.required_apis
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create node pools for standard GKE clusters
resource "google_container_node_pool" "primary_nodes" {
  for_each = var.gke_autopilot_enabled ? {} : local.cluster_names

  name       = "${each.value}-primary-pool"
  location   = var.zone
  cluster    = google_container_cluster.gke_standard_clusters[each.key].name
  project    = var.project_id
  node_count = each.key == "prod" ? 3 : 2

  node_config {
    preemptible  = each.key != "prod"
    machine_type = each.key == "prod" ? "e2-standard-4" : "e2-standard-2"

    # Google service account for node pools
    service_account = google_service_account.gke_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Shielded nodes configuration for production
    dynamic "shielded_instance_config" {
      for_each = each.key == "prod" && var.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }

    labels = merge(local.common_labels, {
      environment = each.key
    })

    tags = ["gke-node", "${each.key}-node"]
  }

  # Auto-scaling configuration
  autoscaling {
    min_node_count = each.key == "prod" ? 2 : 1
    max_node_count = each.key == "prod" ? 10 : 5
  }

  # Node management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [
    google_container_cluster.gke_standard_clusters
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Service account for GKE nodes (used only for standard clusters)
resource "google_service_account" "gke_service_account" {
  account_id   = "gke-nodes-${local.name_suffix}"
  display_name = "GKE Node Service Account"
  description  = "Service account for GKE node pools"
  project      = var.project_id
}

# IAM bindings for GKE node service account
resource "google_project_iam_member" "gke_service_account_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_service_account.email}"
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_repository" {
  location      = var.region
  repository_id = local.repository_name
  description   = "Enterprise application container images repository"
  format        = "DOCKER"
  project       = var.project_id

  labels = merge(local.common_labels, {
    repository-type = "docker"
    purpose        = "enterprise-cicd"
  })

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create Cloud Source Repositories
resource "google_sourcerepo_repository" "source_repositories" {
  for_each = toset(var.source_repo_names)

  name    = "${each.value}-${local.name_suffix}"
  project = var.project_id

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create service account for Cloud Build
resource "google_service_account" "cloudbuild_service_account" {
  account_id   = "${var.service_account_name}-${local.name_suffix}"
  display_name = "Cloud Build Deploy Service Account"
  description  = "Service account for Cloud Build deployment operations"
  project      = var.project_id
}

# IAM roles for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/clouddeploy.operator",
    "roles/container.clusterAdmin",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/storage.admin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}

# Allow Cloud Build default service account to use custom service account
resource "google_service_account_iam_member" "cloudbuild_sa_user" {
  service_account_id = google_service_account.cloudbuild_service_account.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create Cloud Deploy targets for each environment
resource "google_clouddeploy_target" "deployment_targets" {
  for_each = local.cluster_names

  location = var.region
  name     = "${each.key}-target-${local.name_suffix}"
  project  = var.project_id

  description = "${title(each.key)} environment deployment target"

  # GKE cluster configuration
  gke {
    cluster = var.gke_autopilot_enabled ? google_container_cluster.gke_clusters[each.key].id : google_container_cluster.gke_standard_clusters[each.key].id
  }

  # Require approval for production deployments
  require_approval = each.key == "prod" ? true : false

  # Labels and annotations
  labels = merge(local.common_labels, {
    environment = each.key
    target-type = "gke"
  })

  annotations = var.annotations

  depends_on = [
    google_project_service.required_apis,
    google_container_cluster.gke_clusters,
    google_container_cluster.gke_standard_clusters
  ]
}

# Create Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "enterprise_pipeline" {
  location = var.region
  name     = local.pipeline_name
  project  = var.project_id

  description = "Enterprise deployment pipeline for multi-environment application delivery"

  # Serial pipeline configuration with progressive deployment
  serial_pipeline {
    dynamic "stages" {
      for_each = var.environments
      content {
        target_id = google_clouddeploy_target.deployment_targets[stages.value].name
        profiles  = []

        # Deploy parameters for environment-specific configuration
        deploy_parameters {
          values = {
            environment = stages.value
            namespace   = "default"
          }
          match_target_labels = {}
        }
      }
    }
  }

  # Labels and annotations
  labels      = local.common_labels
  annotations = var.annotations

  depends_on = [
    google_clouddeploy_target.deployment_targets
  ]
}

# Create Cloud Build trigger for automated deployments
resource "google_cloudbuild_trigger" "deployment_trigger" {
  name        = "${var.build_trigger_name}-${local.name_suffix}"
  location    = var.region
  description = "Enterprise deployment pipeline trigger for automated CI/CD"
  project     = var.project_id

  # Use the pipeline templates repository
  trigger_template {
    branch_name = "main"
    repo_name   = google_sourcerepo_repository.source_repositories["sample-app"].name
  }

  # Build configuration using inline build steps
  build {
    # Build the container image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/$${_SERVICE_NAME}:$${SHORT_SHA}",
        "."
      ]
      timeout = "300s"
    }

    # Push the container image to Artifact Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/$${_SERVICE_NAME}:$${SHORT_SHA}"
      ]
      timeout = "300s"
    }

    # Prepare Kubernetes manifests using gke-deploy
    step {
      name = "gcr.io/cloud-builders/gke-deploy"
      args = [
        "prepare",
        "--filename=k8s/",
        "--image=${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/$${_SERVICE_NAME}:$${SHORT_SHA}",
        "--app=$${_SERVICE_NAME}",
        "--version=$${SHORT_SHA}",
        "--namespace=$${_NAMESPACE}",
        "--output=output"
      ]
      timeout = "300s"
    }

    # Create Cloud Deploy release
    step {
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      entrypoint = "gcloud"
      args = [
        "deploy",
        "releases",
        "create",
        "release-$${SHORT_SHA}",
        "--delivery-pipeline=${google_clouddeploy_delivery_pipeline.enterprise_pipeline.name}",
        "--region=${var.region}",
        "--source=output"
      ]
      timeout = "600s"
    }

    # Build substitutions
    substitutions = {
      _SERVICE_NAME = "sample-app"
      _NAMESPACE    = "default"
    }

    # Build options
    options {
      logging       = "CLOUD_LOGGING_ONLY"
      machine_type  = var.cloudbuild_machine_type
      substitution_option = "ALLOW_LOOSE"
    }

    # Build timeout
    timeout = var.cloudbuild_timeout
  }

  # Use custom service account
  service_account = google_service_account.cloudbuild_service_account.id

  # Build trigger filters
  ignored_files = [
    "**/*.md",
    "docs/**",
    "terraform/**"
  ]

  included_files = [
    "src/**",
    "k8s/**",
    "Dockerfile",
    "package.json"
  ]

  depends_on = [
    google_project_service.required_apis,
    google_sourcerepo_repository.source_repositories,
    google_clouddeploy_delivery_pipeline.enterprise_pipeline,
    google_artifact_registry_repository.container_repository,
    google_service_account_iam_member.cloudbuild_sa_user
  ]
}

# Create IAM policy for Artifact Registry repository access
resource "google_artifact_registry_repository_iam_member" "repository_access" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer"
  ])

  project    = var.project_id
  location   = google_artifact_registry_repository.container_repository.location
  repository = google_artifact_registry_repository.container_repository.name
  role       = each.value
  member     = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}

# Grant Cloud Build service account access to GKE clusters
resource "google_container_cluster_iam_member" "cluster_access" {
  for_each = local.cluster_names

  cluster = var.gke_autopilot_enabled ? google_container_cluster.gke_clusters[each.key].name : google_container_cluster.gke_standard_clusters[each.key].name
  location = var.gke_autopilot_enabled ? google_container_cluster.gke_clusters[each.key].location : google_container_cluster.gke_standard_clusters[each.key].location
  project  = var.project_id
  role     = "roles/container.clusterAdmin"
  member   = "serviceAccount:${google_service_account.cloudbuild_service_account.email}"
}