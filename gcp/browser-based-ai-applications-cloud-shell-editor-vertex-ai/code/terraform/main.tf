# Main Terraform configuration for browser-based AI applications
# Creates infrastructure for Cloud Shell Editor development with Vertex AI integration

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    recipe-id   = "f7e8a9b2"
  })
  
  # API services required for the browser-based AI application
  required_apis = var.enable_apis ? [
    "cloudbuild.googleapis.com",           # Cloud Build for CI/CD
    "run.googleapis.com",                  # Cloud Run for serverless hosting
    "aiplatform.googleapis.com",           # Vertex AI for ML capabilities
    "artifactregistry.googleapis.com",     # Artifact Registry for container storage
    "secretmanager.googleapis.com",        # Secret Manager for configuration
    "cloudresourcemanager.googleapis.com", # Resource Manager for project management
    "serviceusage.googleapis.com",         # Service Usage for API management
    "iam.googleapis.com",                  # IAM for access control
    "compute.googleapis.com"               # Compute Engine for underlying infrastructure
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent APIs from being disabled when Terraform is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "ai_app_repo" {
  count      = var.enable_apis ? 1 : 0
  depends_on = [google_project_service.required_apis]
  
  location      = var.region
  repository_id = "${var.repository_name}-${local.resource_suffix}"
  description   = "Container repository for AI chat assistant application"
  format        = var.artifact_registry_format
  
  labels = local.common_labels
  
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    
    most_recent_versions {
      keep_count = 10
    }
  }
  
  cleanup_policies {
    id     = "delete-old-versions"
    action = "DELETE"
    
    condition {
      older_than = "2592000s" # 30 days
    }
  }
}

# IAM role for Cloud Build service account to access Vertex AI
resource "google_project_iam_member" "cloudbuild_vertex_ai" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# IAM role for Cloud Build to deploy to Cloud Run
resource "google_project_iam_member" "cloudbuild_run_admin" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# IAM role for Cloud Build to act as service account user
resource "google_project_iam_member" "cloudbuild_sa_user" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# Custom service account for Cloud Run with minimal permissions
resource "google_service_account" "cloud_run_sa" {
  count        = var.enable_apis ? 1 : 0
  account_id   = "ai-app-runner-${local.resource_suffix}"
  display_name = "AI Chat Assistant Cloud Run Service Account"
  description  = "Service account for Cloud Run AI application with Vertex AI access"
  
  depends_on = [google_project_service.required_apis]
}

# Grant Vertex AI user role to Cloud Run service account
resource "google_project_iam_member" "cloud_run_vertex_ai" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}

# Grant monitoring writer role for observability
resource "google_project_iam_member" "cloud_run_monitoring" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}

# Grant logging writer role for application logs
resource "google_project_iam_member" "cloud_run_logging" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}

# Cloud Build trigger for automated deployment (requires repository connection)
resource "google_cloudbuild_trigger" "ai_app_trigger" {
  count       = var.enable_apis ? 1 : 0
  name        = "ai-app-deploy-${local.resource_suffix}"
  description = "Trigger for automated AI application deployment"
  location    = var.region
  
  # Manual trigger - can be connected to repository later
  source_to_build {
    uri       = "https://github.com/placeholder/ai-app-repo"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = "https://github.com/placeholder/ai-app-repo"
    revision  = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  substitutions = {
    _SERVICE_NAME = var.service_name
    _REGION       = var.region
    _REPO_NAME    = google_artifact_registry_repository.ai_app_repo[0].repository_id
  }
  
  # Build configuration for AI application
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:$COMMIT_SHA",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:$COMMIT_SHA"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", var.service_name,
        "--image=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_repo[0].repository_id}/${var.service_name}:$COMMIT_SHA",
        "--region=${var.region}",
        "--platform=managed",
        "--allow-unauthenticated=${var.allow_unauthenticated}",
        "--memory=${var.cloud_run_memory}",
        "--cpu=${var.cloud_run_cpu}",
        "--max-instances=${var.cloud_run_max_instances}",
        "--min-instances=${var.cloud_run_min_instances}",
        "--service-account=${google_service_account.cloud_run_sa[0].email}",
        "--set-env-vars=GOOGLE_CLOUD_PROJECT=${var.project_id},GOOGLE_CLOUD_REGION=${var.vertex_ai_location}"
      ]
    }
    
    timeout = "${var.cloud_build_timeout}s"
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.ai_app_repo
  ]
}

# Cloud Run service for AI chat assistant
resource "google_cloud_run_v2_service" "ai_chat_service" {
  count    = var.enable_apis ? 1 : 0
  name     = "${var.service_name}-${local.resource_suffix}"
  location = var.region
  
  labels = local.common_labels
  
  template {
    labels = local.common_labels
    
    # Service account for secure Vertex AI access
    service_account = google_service_account.cloud_run_sa[0].email
    
    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    containers {
      # Placeholder image - will be updated by Cloud Build
      image = "gcr.io/cloudrun/hello"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle = false
      }
      
      # Container port configuration
      ports {
        container_port = 8080
        name           = "http1"
      }
      
      # Environment variables for AI application
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GOOGLE_CLOUD_REGION"
        value = var.vertex_ai_location
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 10
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 60
        timeout_seconds       = 10
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
    
    # Execution environment configuration
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # VPC connector configuration (if needed for private resources)
    # vpc_access {
    #   connector = google_vpc_access_connector.ai_app_connector[0].id
    #   egress    = "ALL_TRAFFIC"
    # }
  }
  
  # Traffic allocation (100% to latest revision)
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.cloud_run_sa
  ]
}

# IAM policy for public access (if enabled)
resource "google_cloud_run_service_iam_member" "public_access" {
  count    = var.enable_apis && var.allow_unauthenticated ? 1 : 0
  location = google_cloud_run_v2_service.ai_chat_service[0].location
  service  = google_cloud_run_v2_service.ai_chat_service[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Data source for current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Secret Manager secret for application configuration (optional)
resource "google_secret_manager_secret" "app_config" {
  count     = var.enable_apis ? 1 : 0
  secret_id = "ai-app-config-${local.resource_suffix}"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Secret version with basic configuration
resource "google_secret_manager_secret_version" "app_config_version" {
  count  = var.enable_apis ? 1 : 0
  secret = google_secret_manager_secret.app_config[0].id
  
  secret_data = jsonencode({
    vertex_ai_location = var.vertex_ai_location
    environment       = var.environment
    service_name      = var.service_name
    max_tokens        = 1000
    temperature       = 0.7
    top_p            = 0.8
  })
}

# Grant Cloud Run service account access to the secret
resource "google_secret_manager_secret_iam_member" "cloud_run_secret_access" {
  count     = var.enable_apis ? 1 : 0
  secret_id = google_secret_manager_secret.app_config[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa[0].email}"
}