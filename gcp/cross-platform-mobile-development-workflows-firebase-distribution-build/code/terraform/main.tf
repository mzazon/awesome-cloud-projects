# Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build
# This Terraform configuration deploys a complete mobile CI/CD pipeline infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Create unique names for resources to avoid conflicts
  unique_suffix = random_id.suffix.hex
  
  # Construct resource names with suffix
  repository_name_unique        = "${var.repository_name}-${local.unique_suffix}"
  build_service_account_unique  = "${var.build_service_account_name}-${local.unique_suffix}"
  artifact_bucket_name_unique   = var.artifact_bucket_name != "" ? var.artifact_bucket_name : "mobile-artifacts-${var.project_id}-${local.unique_suffix}"
  notification_topic_name_unique = "${var.notification_topic_name}-${local.unique_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform = "true"
    component = "mobile-cicd"
  })
  
  # Required Google Cloud APIs for the mobile CI/CD pipeline
  required_apis = [
    "firebase.googleapis.com",           # Firebase services
    "cloudbuild.googleapis.com",         # Cloud Build for CI/CD
    "sourcerepo.googleapis.com",         # Cloud Source Repositories
    "testing.googleapis.com",            # Firebase Test Lab
    "androidpublisher.googleapis.com",   # Android Publisher API for app distribution
    "secretmanager.googleapis.com",      # Secret Manager for credentials
    "storage.googleapis.com",            # Cloud Storage for artifacts
    "pubsub.googleapis.com",            # Pub/Sub for notifications
    "artifactregistry.googleapis.com",   # Artifact Registry for container images
    "containeranalysis.googleapis.com",  # Container Analysis for vulnerability scanning
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Don't disable services when destroying to avoid breaking dependencies
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Initialize Firebase project
resource "google_firebase_project" "mobile_project" {
  provider = google-beta
  project  = var.project_id
  
  # Firebase project must be created after required APIs are enabled
  depends_on = [google_project_service.required_apis]
}

# Create Android application in Firebase
resource "google_firebase_android_app" "android_app" {
  provider = google-beta
  
  project      = google_firebase_project.mobile_project.project
  display_name = var.android_app_display_name
  package_name = var.android_package_name
  
  # Optional: SHA certificate hashes for app signing (add these if you have them)
  # sha1_hashes   = ["your-sha1-hash"]
  # sha256_hashes = ["your-sha256-hash"]
}

# Create iOS application in Firebase
resource "google_firebase_ios_app" "ios_app" {
  provider = google-beta
  
  project      = google_firebase_project.mobile_project.project
  display_name = var.ios_app_display_name
  bundle_id    = var.ios_bundle_id
  
  # App Store ID can be added later when the app is published
  # app_store_id = "123456789"
}

# Create Cloud Source Repository for the mobile application
resource "google_sourcerepo_repository" "mobile_repo" {
  name    = local.repository_name_unique
  project = var.project_id
  
  # Pub/Sub notifications for repository changes (optional)
  dynamic "pubsub_configs" {
    for_each = var.enable_build_notifications ? [1] : []
    content {
      topic                 = google_pubsub_topic.build_notifications[0].id
      message_format        = "JSON"
      service_account_email = google_service_account.build_service_account.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create dedicated service account for Cloud Build
resource "google_service_account" "build_service_account" {
  account_id   = local.build_service_account_unique
  display_name = "Mobile CI/CD Build Service Account"
  description  = "Service account for mobile application CI/CD builds"
  project      = var.project_id
}

# Grant necessary IAM roles to the build service account
resource "google_project_iam_member" "build_service_account_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",     # Cloud Build execution
    "roles/source.reader",                 # Source repository access
    "roles/storage.admin",                 # Storage bucket access for artifacts
    "roles/firebase.admin",                # Firebase administration
    "roles/firebase.testLab.testRunner",   # Firebase Test Lab execution
    "roles/firebase.appDistribution.releaser", # Firebase App Distribution
    "roles/secretmanager.secretAccessor",  # Secret Manager access
    "roles/pubsub.publisher",             # Pub/Sub notifications
    "roles/artifactregistry.writer",       # Artifact Registry push
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.build_service_account.email}"
}

# Create Cloud Storage bucket for build artifacts
resource "google_storage_bucket" "build_artifacts" {
  name          = local.artifact_bucket_name_unique
  location      = var.artifact_bucket_location
  project       = var.project_id
  force_destroy = true
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30 # Delete artifacts older than 30 days
    }
  }
  
  # Enable versioning for important artifacts
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for build notifications (optional)
resource "google_pubsub_topic" "build_notifications" {
  count = var.enable_build_notifications ? 1 : 0
  
  name    = local.notification_topic_name_unique
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Build trigger for main branch
resource "google_cloudbuild_trigger" "main_branch_trigger" {
  name        = var.build_trigger_name
  project     = var.project_id
  description = "Trigger for main branch builds with full CI/CD pipeline"
  
  # Configure trigger to respond to source repository changes
  trigger_template {
    repo_name   = google_sourcerepo_repository.mobile_repo.name
    branch_name = var.main_branch_pattern
  }
  
  # Reference to the build configuration file
  filename = var.build_config_filename
  
  # Enable build logs for Firebase App Distribution
  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"
  
  # Substitution variables for the build
  substitutions = {
    _ANDROID_APP_ID          = google_firebase_android_app.android_app.app_id
    _IOS_APP_ID             = google_firebase_ios_app.ios_app.app_id
    _PROJECT_ID             = var.project_id
    _ARTIFACT_BUCKET        = google_storage_bucket.build_artifacts.name
    _ENVIRONMENT            = var.environment
    _NOTIFICATION_TOPIC     = var.enable_build_notifications ? google_pubsub_topic.build_notifications[0].name : ""
  }
  
  # Configure service account for builds
  service_account = google_service_account.build_service_account.id
  
  tags = ["main-branch", "production-ready"]
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.build_service_account_roles
  ]
}

# Create Cloud Build trigger for feature branches
resource "google_cloudbuild_trigger" "feature_branch_trigger" {
  name        = var.feature_branch_trigger_name
  project     = var.project_id
  description = "Trigger for feature branch builds with testing and validation"
  
  # Configure trigger for feature branches
  trigger_template {
    repo_name   = google_sourcerepo_repository.mobile_repo.name
    branch_name = var.feature_branch_pattern
  }
  
  # Reference to the build configuration file
  filename = var.build_config_filename
  
  # Substitution variables for feature branch builds
  substitutions = {
    _ANDROID_APP_ID          = google_firebase_android_app.android_app.app_id
    _IOS_APP_ID             = google_firebase_ios_app.ios_app.app_id
    _PROJECT_ID             = var.project_id
    _ARTIFACT_BUCKET        = google_storage_bucket.build_artifacts.name
    _ENVIRONMENT            = "feature"
    _NOTIFICATION_TOPIC     = var.enable_build_notifications ? google_pubsub_topic.build_notifications[0].name : ""
    _FEATURE_BUILD          = "true"
  }
  
  # Configure service account for builds
  service_account = google_service_account.build_service_account.id
  
  tags = ["feature-branch", "testing"]
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.build_service_account_roles
  ]
}

# Create Secret Manager secret for Firebase service account key (if needed)
resource "google_secret_manager_secret" "firebase_service_account" {
  secret_id = "firebase-service-account-key"
  project   = var.project_id
  
  replication {
    automatic = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Grant the build service account access to the secret
resource "google_secret_manager_secret_iam_member" "firebase_secret_access" {
  secret_id = google_secret_manager_secret.firebase_service_account.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.build_service_account.email}"
  project   = var.project_id
}

# Create Artifact Registry repository for container images (if using containerized builds)
resource "google_artifact_registry_repository" "mobile_images" {
  location      = var.region
  repository_id = "mobile-build-images"
  description   = "Repository for mobile CI/CD container images"
  format        = "DOCKER"
  project       = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Configure Binary Authorization policy (if enabled)
resource "google_binary_authorization_policy" "mobile_policy" {
  count = var.enable_binary_authorization ? 1 : 0
  
  project = var.project_id
  
  # Default admission rule - require attestations
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.build_attestor[0].name
    ]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Binary Authorization attestor (if enabled)
resource "google_binary_authorization_attestor" "build_attestor" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name    = "mobile-build-attestor"
  project = var.project_id
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.build_note[0].name
    
    public_keys {
      ascii_armored_pgp_public_key = file("${path.module}/attestor-public-key.pgp") # You need to provide this
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Container Analysis note for attestations (if Binary Authorization is enabled)
resource "google_container_analysis_note" "build_note" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name    = "mobile-build-note"
  project = var.project_id
  
  attestation_authority {
    hint {
      human_readable_name = "Mobile Build Attestor"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Output important resource information for reference