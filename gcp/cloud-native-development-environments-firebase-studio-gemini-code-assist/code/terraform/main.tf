# Main Terraform Configuration for Firebase Studio and Gemini Code Assist Development Environment
# This file creates all the necessary infrastructure components for a cloud-native development environment

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Data source to get the current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "firebase.googleapis.com",
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "generativelanguage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "containeranalysis.googleapis.com",
    "binaryauthorization.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  # Disable the service when the resource is destroyed
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create VPC Network for the development environment
resource "google_compute_network" "firebase_studio_vpc" {
  name                    = "${var.vpc_name}-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  description             = "VPC for Firebase Studio development environment"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create subnet for the development environment
resource "google_compute_subnetwork" "firebase_studio_subnet" {
  name          = "${var.subnet_name}-${random_id.suffix.hex}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.firebase_studio_vpc.id
  description   = "Subnet for Firebase Studio development environment"
  
  # Enable Private Google Access for accessing Google APIs
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for the development environment
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-${random_id.suffix.hex}"
  network = google_compute_network.firebase_studio_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  description   = "Allow internal communication within the VPC"
}

# Create firewall rule for Cloud Run health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks-${random_id.suffix.hex}"
  network = google_compute_network.firebase_studio_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["cloud-run-service"]
  description   = "Allow health checks from Google Cloud Load Balancer"
}

# Create Cloud Source Repository
resource "google_sourcerepo_repository" "ai_app_repo" {
  name = "${var.repository_name}-${random_id.suffix.hex}"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "ai_app_registry" {
  location      = var.region
  repository_id = "${var.artifact_repository_name}-${random_id.suffix.hex}"
  description   = "Container registry for AI applications"
  format        = var.artifact_repository_format
  
  # Enable vulnerability scanning
  depends_on = [time_sleep.wait_for_apis]
}

# Create service account for Gemini Code Assist
resource "google_service_account" "gemini_code_assist" {
  account_id   = "gemini-code-assist-${random_id.suffix.hex}"
  display_name = "Gemini Code Assist Service Account"
  description  = "Service account for AI-powered development assistance"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Grant necessary permissions to the Gemini Code Assist service account
resource "google_project_iam_member" "gemini_code_assist_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/ml.developer",
    "roles/serviceusage.serviceUsageConsumer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gemini_code_assist.email}"
}

# Create service account for Cloud Build
resource "google_service_account" "cloud_build" {
  account_id   = "cloud-build-sa-${random_id.suffix.hex}"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Grant necessary permissions to the Cloud Build service account
resource "google_project_iam_member" "cloud_build_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
    "roles/source.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Create Cloud Build trigger for continuous integration
resource "google_cloudbuild_trigger" "ai_app_build_trigger" {
  name        = "${var.build_trigger_name}-${random_id.suffix.hex}"
  description = "Automated build and deployment trigger for AI applications"
  
  # Trigger on push to main branch
  trigger_template {
    branch_name = var.build_trigger_branch
    repo_name   = google_sourcerepo_repository.ai_app_repo.name
  }
  
  # Build configuration
  build {
    step {
      name = "node:18"
      entrypoint = "npm"
      args = ["install"]
    }
    
    step {
      name = "node:18"
      entrypoint = "npm"
      args = ["test"]
    }
    
    step {
      name = "node:18"
      entrypoint = "npm"
      args = ["run", "build"]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}/ai-app:latest",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}/ai-app:latest"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", var.cloud_run_service_name,
        "--image", "${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}/ai-app:latest",
        "--region", var.region,
        "--platform", "managed",
        "--allow-unauthenticated",
        "--service-account", google_service_account.cloud_build.email
      ]
    }
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }
  
  service_account = google_service_account.cloud_build.id
  
  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    time_sleep.wait_for_apis
  ]
}

# Create Cloud Run service for the AI application
resource "google_cloud_run_service" "ai_app" {
  name     = "${var.cloud_run_service_name}-${random_id.suffix.hex}"
  location = var.region
  
  template {
    spec {
      service_account_name = google_service_account.cloud_build.email
      
      containers {
        image = "${google_artifact_registry_repository.ai_app_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_app_registry.repository_id}/ai-app:latest"
        
        resources {
          limits = {
            cpu    = var.cloud_run_cpu
            memory = var.cloud_run_memory
          }
        }
        
        ports {
          container_port = 8080
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "REGION"
          value = var.region
        }
        
        env {
          name  = "GEMINI_MODEL"
          value = var.gemini_model_name
        }
      }
      
      container_concurrency = 80
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = tostring(var.cloud_run_max_instances)
        "run.googleapis.com/network-interfaces" = jsonencode([{
          network    = google_compute_network.firebase_studio_vpc.name
          subnetwork = google_compute_subnetwork.firebase_studio_subnet.name
          tags       = ["cloud-run-service"]
        }])
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    time_sleep.wait_for_apis
  ]
}

# Allow unauthenticated access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.ai_app.name
  location = google_cloud_run_service.ai_app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create Firebase project configuration
resource "google_firebase_project" "firebase_project" {
  provider = google-beta
  project  = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Firebase project location
resource "google_firebase_project_location" "firebase_location" {
  provider    = google-beta
  project     = google_firebase_project.firebase_project.project
  location_id = var.firebase_location
  
  depends_on = [google_firebase_project.firebase_project]
}

# Create Firestore database
resource "google_firestore_database" "firestore_db" {
  provider    = google-beta
  project     = google_firebase_project.firebase_project.project
  name        = "(default)"
  location_id = var.firebase_location
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [google_firebase_project_location.firebase_location]
}

# Create Firebase web app
resource "google_firebase_web_app" "firebase_web_app" {
  provider        = google-beta
  project         = google_firebase_project.firebase_project.project
  display_name    = "AI Development Environment Web App"
  deletion_policy = "DELETE"
  
  depends_on = [google_firebase_project.firebase_project]
}

# Create Secret Manager secret for Firebase config
resource "google_secret_manager_secret" "firebase_config" {
  secret_id = "firebase-config-${random_id.suffix.hex}"
  
  replication {
    auto {}
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Store Firebase web app config in Secret Manager
resource "google_secret_manager_secret_version" "firebase_config_version" {
  secret = google_secret_manager_secret.firebase_config.id
  secret_data = jsonencode({
    apiKey            = google_firebase_web_app.firebase_web_app.api_key
    authDomain        = "${var.project_id}.firebaseapp.com"
    projectId         = var.project_id
    storageBucket     = "${var.project_id}.appspot.com"
    messagingSenderId = data.google_project.current.number
    appId             = google_firebase_web_app.firebase_web_app.app_id
  })
  
  depends_on = [google_firebase_web_app.firebase_web_app]
}

# Enable Binary Authorization if specified
resource "google_binary_authorization_policy" "binary_authorization" {
  count = var.enable_binary_authorization ? 1 : 0
  
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.attestor[0].name
    ]
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Binary Authorization attestor
resource "google_binary_authorization_attestor" "attestor" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name = "firebase-studio-attestor-${random_id.suffix.hex}"
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note[0].name
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Container Analysis note for attestor
resource "google_container_analysis_note" "attestor_note" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name = "firebase-studio-attestor-note-${random_id.suffix.hex}"
  
  attestation_authority {
    hint {
      human_readable_name = "Firebase Studio Development Environment Attestor"
    }
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Cloud Monitoring workspace
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create alert policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High CPU Usage Alert"
  
  conditions {
    display_name = "CPU usage above 80%"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${google_cloud_run_service.ai_app.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_notification[0].name]
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create log sink for centralized logging
resource "google_logging_project_sink" "ai_app_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "ai-app-logs-${random_id.suffix.hex}"
  destination = "storage.googleapis.com/${google_storage_bucket.log_bucket[0].name}"
  
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.ai_app.name}\""
  
  unique_writer_identity = true
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Cloud Storage bucket for logs
resource "google_storage_bucket" "log_bucket" {
  count = var.enable_monitoring ? 1 : 0
  
  name          = "ai-app-logs-${var.project_id}-${random_id.suffix.hex}"
  location      = var.region
  force_destroy = true
  
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Grant write access to log sink service account
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.log_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.ai_app_logs[0].writer_identity
}

# Create billing budget for cost management
resource "google_billing_budget" "development_budget" {
  count = var.enable_cost_alerts ? 1 : 0
  
  billing_account = data.google_project.current.billing_account
  display_name    = "Firebase Studio Development Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Apply labels to all resources
locals {
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.resource_prefix
    created-by  = "terraform"
    suffix      = random_id.suffix.hex
  })
}

# Output important resource information
output "project_id" {
  description = "The project ID"
  value       = var.project_id
}

output "region" {
  description = "The deployment region"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}