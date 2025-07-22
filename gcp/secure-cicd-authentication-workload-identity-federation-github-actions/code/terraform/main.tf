# Main Terraform configuration for Workload Identity Federation with GitHub Actions
# This configuration sets up keyless authentication between GitHub Actions and Google Cloud

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Generate unique resource names using provided values or defaults with random suffix
  wif_pool_id       = var.workload_identity_pool_id != "" ? var.workload_identity_pool_id : "${var.resource_prefix}-pool-${random_id.suffix.hex}"
  wif_provider_id   = var.workload_identity_provider_id != "" ? var.workload_identity_provider_id : "${var.resource_prefix}-provider-${random_id.suffix.hex}"
  service_account_id = var.service_account_id != "" ? var.service_account_id : "${var.resource_prefix}-sa-${random_id.suffix.hex}"
  artifact_repo_name = var.artifact_repository_name != "" ? var.artifact_repository_name : "${var.resource_prefix}-repo-${random_id.suffix.hex}"
  cloud_run_service = var.cloud_run_service_name != "" ? var.cloud_run_service_name : "${var.resource_prefix}-app-${random_id.suffix.hex}"
  
  # GitHub repository configuration
  github_repo_full = "${var.github_repo_owner}/${var.github_repo_name}"
  all_github_repos = concat([local.github_repo_full], var.additional_github_repos)
  
  # Standard CI/CD IAM roles required for the pipeline
  default_iam_roles = [
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer", 
    "roles/run.developer"
  ]
  
  # Combine default and custom IAM roles
  all_iam_roles = concat(local.default_iam_roles, var.custom_iam_roles)
  
  # Required Google Cloud APIs for the solution
  required_apis = [
    "iam.googleapis.com",
    "cloudbuild.googleapis.com", 
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com"
  ]
  
  # Default tags with resource identification
  default_tags = {
    "managed-by"           = "terraform"
    "solution"            = "workload-identity-federation"
    "github-repo"         = local.github_repo_full
    "environment"         = "demo"
  }
  
  # Merge default and custom tags
  resource_tags = merge(local.default_tags, var.tags)
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling the service on resource destruction
  disable_on_destroy = false
  
  # Ensure proper dependency management
  disable_dependent_services = false
}

# Create Workload Identity Pool
# This pool manages external identities that can authenticate to Google Cloud
resource "google_iam_workload_identity_pool" "github_pool" {
  provider = google-beta
  
  project                   = var.project_id
  workload_identity_pool_id = local.wif_pool_id
  display_name              = var.workload_identity_pool_display_name
  description               = "Pool for GitHub Actions workflows - managed by Terraform"
  
  # Pool is global and doesn't require a specific location
  # It provides a namespace for organizing federated identities
  
  depends_on = [google_project_service.required_apis]
}

# Create GitHub OIDC Provider within the Workload Identity Pool
# This establishes the trust relationship with GitHub's OIDC endpoint
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  provider = google-beta
  
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = local.wif_provider_id
  display_name                       = var.workload_identity_provider_display_name
  description                        = "GitHub OIDC provider for ${local.github_repo_full} - managed by Terraform"
  
  # Configure attribute mapping to extract claims from GitHub OIDC tokens
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository" 
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.workflow"         = "assertion.workflow"
    "attribute.ref"              = "assertion.ref"
    "attribute.sha"              = "assertion.sha"
  }
  
  # Restrict access to specific repository owner for enhanced security
  attribute_condition = "assertion.repository_owner == '${var.github_repo_owner}'"
  
  # Configure OIDC provider settings
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
    
    # GitHub's OIDC endpoint uses the default audiences
    # No additional audience configuration required
  }
  
  depends_on = [google_iam_workload_identity_pool.github_pool]
}

# Create dedicated service account for GitHub Actions
# This account will have the minimal permissions needed for CI/CD operations
resource "google_service_account" "github_actions" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Service account for GitHub Actions CI/CD workflows - managed by Terraform"
}

# Grant necessary IAM roles to the service account for CI/CD operations
# Using for_each to create individual bindings for better granular control
resource "google_project_iam_member" "github_actions_roles" {
  for_each = toset(local.all_iam_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
  
  depends_on = [google_service_account.github_actions]
}

# Grant Workload Identity User role to allow GitHub repositories to impersonate the service account
# This creates the actual federation binding between external identities and the service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  for_each = toset(local.all_github_repos)
  
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${each.value}"
  
  depends_on = [
    google_iam_workload_identity_pool_provider.github_provider,
    google_service_account.github_actions
  ]
}

# Create Artifact Registry repository for container images
# This provides secure, private storage for CI/CD artifacts with vulnerability scanning
resource "google_artifact_registry_repository" "container_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = local.artifact_repo_name
  description   = var.artifact_repository_description
  format        = "DOCKER"
  
  # Enable vulnerability scanning for enhanced security
  docker_config {
    immutable_tags = false
  }
  
  labels = local.resource_tags
  
  depends_on = [google_project_service.required_apis]
}

# Create a basic Cloud Run service placeholder for demonstration
# This shows the complete CI/CD pipeline endpoint
resource "google_cloud_run_v2_service" "demo_app" {
  project  = var.project_id
  name     = local.cloud_run_service
  location = var.region
  
  # Deletion policy to allow easy cleanup
  deletion_protection = false
  
  template {
    # Configure scaling settings
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Container configuration
    containers {
      # Use a simple hello-world image initially
      # This will be replaced by CI/CD pipeline with actual application image
      image = "gcr.io/cloudrun/hello"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
      
      # Container port configuration
      ports {
        container_port = 8080
      }
      
      # Environment variables for the application
      env {
        name  = "ENVIRONMENT"
        value = "production"
      }
      
      env {
        name  = "APP_VERSION"
        value = "1.0.0"
      }
    }
    
    # Service account for the Cloud Run service
    service_account = google_service_account.github_actions.email
  }
  
  # Traffic configuration - route 100% to latest revision
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.github_actions
  ]
}

# Configure IAM policy for Cloud Run service to allow unauthenticated access
# This enables public access to the deployed application
resource "google_cloud_run_service_iam_member" "public_access" {
  project  = var.project_id
  location = google_cloud_run_v2_service.demo_app.location
  service  = google_cloud_run_v2_service.demo_app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  depends_on = [google_cloud_run_v2_service.demo_app]
}