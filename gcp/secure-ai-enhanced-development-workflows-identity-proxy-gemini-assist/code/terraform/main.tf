# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  app_name_full   = "${var.app_name}-${local.resource_suffix}"
  workstation_name_full = "${var.workstation_name}-${local.resource_suffix}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = var.project_id
  })
  
  # Secret names
  secret_names = {
    db  = "app-secrets-db-${local.resource_suffix}"
    api = "app-secrets-api-${local.resource_suffix}"
  }
  
  # Service account names
  service_accounts = {
    app           = "secure-app-sa-${local.resource_suffix}"
    gemini        = "gemini-code-assist-sa-${local.resource_suffix}"
    cloud_build   = "cloudbuild-sa-${local.resource_suffix}"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "workstations.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "sourcerepo.googleapis.com",
    "iap.googleapis.com",
    "compute.googleapis.com",
    "aiplatform.googleapis.com",
    "container.googleapis.com",
    "binaryauthorization.googleapis.com",
    "cloudbilling.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

#######################
# KMS Configuration
#######################

# Create KMS keyring for encryption
resource "google_kms_key_ring" "secure_dev_keyring" {
  name     = "secure-dev-keyring-${local.resource_suffix}"
  location = var.region
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create KMS key for secret encryption
resource "google_kms_crypto_key" "secret_encryption_key" {
  name     = "secret-encryption-key"
  key_ring = google_kms_key_ring.secure_dev_keyring.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = var.kms_key_rotation_period
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

#######################
# Service Accounts
#######################

# Service account for secure application
resource "google_service_account" "secure_app_sa" {
  account_id   = local.service_accounts.app
  display_name = "Secure Application Service Account"
  description  = "Service account for secure development application with secret access"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for Gemini Code Assist
resource "google_service_account" "gemini_code_assist_sa" {
  account_id   = local.service_accounts.gemini
  display_name = "Gemini Code Assist Service Account"
  description  = "Service account for AI-powered development assistance"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for Cloud Build
resource "google_service_account" "cloud_build_sa" {
  account_id   = local.service_accounts.cloud_build
  display_name = "Cloud Build Service Account"
  description  = "Custom service account for Cloud Build with specific permissions"
  
  depends_on = [time_sleep.wait_for_apis]
}

#######################
# IAM Role Bindings
#######################

# Grant Secret Manager access to application service account
resource "google_project_iam_member" "app_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.secure_app_sa.email}"
}

# Grant AI Platform access to Gemini service account
resource "google_project_iam_member" "gemini_ai_platform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.gemini_code_assist_sa.email}"
}

# Grant Cloud Build necessary permissions
resource "google_project_iam_member" "cloud_build_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

resource "google_project_iam_member" "cloud_build_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

resource "google_project_iam_member" "cloud_build_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# Grant IAP access to allowed users
resource "google_project_iam_member" "iap_access" {
  count   = length(var.allowed_users)
  project = var.project_id
  role    = "roles/iap.httpsResourceAccessor"
  member  = "user:${var.allowed_users[count.index]}"
}

#######################
# Secrets Management
#######################

# Create secrets for database and API configurations
resource "google_secret_manager_secret" "db_secret" {
  secret_id = local.secret_names.db
  
  labels = local.common_labels
  
  replication {
    automatic = true
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_secret_manager_secret" "api_secret" {
  secret_id = local.secret_names.api
  
  labels = local.common_labels
  
  replication {
    automatic = true
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create secret versions with sample data
resource "google_secret_manager_secret_version" "db_secret_version" {
  secret = google_secret_manager_secret.db_secret.id
  secret_data = "postgresql://username:password@localhost:5432/secure_dev_db"
}

resource "google_secret_manager_secret_version" "api_secret_version" {
  secret = google_secret_manager_secret.api_secret.id
  secret_data = "sample-api-key-${local.resource_suffix}"
}

# Grant secret access to application service account
resource "google_secret_manager_secret_iam_member" "db_secret_access" {
  secret_id = google_secret_manager_secret.db_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secure_app_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "api_secret_access" {
  secret_id = google_secret_manager_secret.api_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secure_app_sa.email}"
}

#######################
# Artifact Registry
#######################

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "secure_dev_images" {
  location      = var.region
  repository_id = "secure-dev-images-${local.resource_suffix}"
  description   = "Secure development container images"
  format        = "DOCKER"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

#######################
# Cloud Source Repositories
#######################

# Create Cloud Source Repository for code storage
resource "google_sourcerepo_repository" "secure_dev_repo" {
  name = "secure-dev-repo-${local.resource_suffix}"
  
  depends_on = [time_sleep.wait_for_apis]
}

#######################
# Cloud Workstations
#######################

# Create Cloud Workstations cluster
resource "google_workstations_workstation_cluster" "secure_dev_cluster" {
  workstation_cluster_id = "secure-dev-cluster-${local.resource_suffix}"
  location               = var.region
  
  network    = "projects/${var.project_id}/global/networks/${var.network_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.subnetwork_name}"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Wait for workstation cluster to be created
resource "time_sleep" "wait_for_workstation_cluster" {
  depends_on = [google_workstations_workstation_cluster.secure_dev_cluster]
  create_duration = "120s"
}

# Create Cloud Workstations configuration
resource "google_workstations_workstation_config" "secure_dev_config" {
  workstation_config_id = "secure-dev-config-${local.resource_suffix}"
  workstation_cluster_id = google_workstations_workstation_cluster.secure_dev_cluster.workstation_cluster_id
  location              = var.region
  
  # Host configuration
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb          = var.workstation_disk_size_gb
      disable_public_ip_addresses = true
      
      service_account = google_service_account.secure_app_sa.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
  
  # Container configuration with Gemini Code Assist
  container {
    image = var.container_image
    
    env = {
      GEMINI_CODE_ASSIST_ENABLED = "true"
      GOOGLE_CLOUD_PROJECT      = var.project_id
      ENVIRONMENT              = var.environment
    }
  }
  
  # Idle timeout configuration
  idle_timeout = "${var.workstation_idle_timeout}s"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_workstation_cluster]
}

# Create workstation instance
resource "google_workstations_workstation" "secure_workstation" {
  workstation_id        = local.workstation_name_full
  workstation_config_id = google_workstations_workstation_config.secure_dev_config.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.secure_dev_cluster.workstation_cluster_id
  location             = var.region
  
  labels = local.common_labels
}

#######################
# Cloud Run Application
#######################

# Deploy secure application to Cloud Run
resource "google_cloud_run_v2_service" "secure_app" {
  name     = local.app_name_full
  location = var.region
  
  labels = local.common_labels
  
  template {
    service_account = google_service_account.secure_app_sa.email
    
    containers {
      # Using a sample Python Flask application image
      # In practice, this would be built from your application code
      image = "gcr.io/google-samples/hello-app:1.0"
      
      ports {
        container_port = 8080
      }
      
      env {
        name  = "DB_SECRET_NAME"
        value = local.secret_names.db
      }
      
      env {
        name  = "API_SECRET_NAME"
        value = local.secret_names.api
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
    }
    
    scaling {
      max_instance_count = var.cloud_run_max_instances
    }
    
    timeout = "${var.cloud_run_timeout_seconds}s"
  }
  
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_secret_manager_secret_version.db_secret_version,
    google_secret_manager_secret_version.api_secret_version,
    google_secret_manager_secret_iam_member.db_secret_access,
    google_secret_manager_secret_iam_member.api_secret_access
  ]
}

# Configure IAM policy for Cloud Run service (no public access)
resource "google_cloud_run_v2_service_iam_binding" "secure_app_invoker" {
  name     = google_cloud_run_v2_service.secure_app.name
  location = google_cloud_run_v2_service.secure_app.location
  role     = "roles/run.invoker"
  
  members = concat(
    ["serviceAccount:${google_service_account.secure_app_sa.email}"],
    [for user in var.allowed_users : "user:${user}"]
  )
}

#######################
# Identity-Aware Proxy Configuration
#######################

# Create OAuth consent screen brand (if it doesn't exist)
resource "google_iap_brand" "oauth_brand" {
  support_email     = var.oauth_support_email != "" ? var.oauth_support_email : data.google_client_config.current.user_email
  application_title = var.oauth_brand_application_title
  project           = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
  
  lifecycle {
    ignore_changes = [support_email]
  }
}

# Create OAuth client for IAP
resource "google_iap_client" "oauth_client" {
  display_name = "IAP OAuth Client for ${local.app_name_full}"
  brand        = google_iap_brand.oauth_brand.name
}

#######################
# Cloud Build Configuration
#######################

# Create Cloud Build trigger for automated deployment
resource "google_cloudbuild_trigger" "secure_app_trigger" {
  name     = "secure-app-build-${local.resource_suffix}"
  description = "Build and deploy secure development application"
  
  trigger_template {
    branch_name = "main"
    repo_name   = google_sourcerepo_repository.secure_dev_repo.name
  }
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_images.repository_id}/secure-dev-app:$SHORT_SHA",
        "."
      ]
      dir = "secure-app"
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_images.repository_id}/secure-dev-app:$SHORT_SHA"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run",
        "deploy",
        local.app_name_full,
        "--image=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_images.repository_id}/secure-dev-app:$SHORT_SHA",
        "--region=${var.region}",
        "--service-account=${google_service_account.secure_app_sa.email}",
        "--no-allow-unauthenticated"
      ]
    }
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }
  
  service_account = google_service_account.cloud_build_sa.id
  
  depends_on = [
    google_artifact_registry_repository.secure_dev_images,
    google_sourcerepo_repository.secure_dev_repo
  ]
}

#######################
# Binary Authorization (Optional)
#######################

# Binary Authorization policy for container image validation
resource "google_binary_authorization_policy" "secure_dev_policy" {
  count = var.enable_binary_authorization ? 1 : 0
  
  admission_whitelist_patterns {
    name_pattern = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_images.repository_id}/*"
  }
  
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.secure_dev_attestor[0].name
    ]
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Binary Authorization attestor for image validation
resource "google_binary_authorization_attestor" "secure_dev_attestor" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name        = "secure-dev-attestor-${local.resource_suffix}"
  description = "Attestor for secure development container images"
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.secure_dev_note[0].name
    
    public_keys {
      ascii_armored_pgp_public_key = file("${path.module}/attestor-public-key.pgp")
    }
  }
}

# Container Analysis note for attestor
resource "google_container_analysis_note" "secure_dev_note" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name = "secure-dev-attestor-note-${local.resource_suffix}"
  
  attestation_authority {
    hint {
      human_readable_name = "Secure Development Attestor"
    }
  }
}

#######################
# Budget and Cost Management
#######################

# Get billing account information
data "google_billing_account" "account" {
  count = var.budget_amount > 0 ? 1 : 0
}

# Create budget for cost monitoring
resource "google_billing_budget" "secure_dev_budget" {
  count = var.budget_amount > 0 ? 1 : 0
  
  billing_account = data.google_billing_account.account[0].id
  display_name    = "Secure Development Environment Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis      = "CURRENT_SPEND"
    }
  }
}

#######################
# Data Sources
#######################

# Get current client configuration
data "google_client_config" "current" {}

# Get project information
data "google_project" "current" {
  project_id = var.project_id
}