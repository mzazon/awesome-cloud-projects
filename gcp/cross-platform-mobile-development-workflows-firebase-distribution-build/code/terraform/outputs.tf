# Outputs for Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build

# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

# Firebase Configuration
output "firebase_project_id" {
  description = "The Firebase project ID"
  value       = google_firebase_project.mobile_project.project
}

output "android_app_id" {
  description = "The Firebase Android app ID"
  value       = google_firebase_android_app.android_app.app_id
}

output "android_package_name" {
  description = "The Android application package name"
  value       = google_firebase_android_app.android_app.package_name
}

output "ios_app_id" {
  description = "The Firebase iOS app ID"
  value       = google_firebase_ios_app.ios_app.app_id
}

output "ios_bundle_id" {
  description = "The iOS application bundle identifier"
  value       = google_firebase_ios_app.ios_app.bundle_id
}

# Source Repository Information
output "source_repository_name" {
  description = "The name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.mobile_repo.name
}

output "source_repository_url" {
  description = "The URL of the Cloud Source Repository"
  value       = google_sourcerepo_repository.mobile_repo.url
}

output "source_repository_clone_url" {
  description = "The clone URL for the Cloud Source Repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.mobile_repo.name}"
}

# Cloud Build Configuration
output "main_branch_trigger_id" {
  description = "The ID of the main branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_branch_trigger.trigger_id
}

output "main_branch_trigger_name" {
  description = "The name of the main branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.main_branch_trigger.name
}

output "feature_branch_trigger_id" {
  description = "The ID of the feature branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.feature_branch_trigger.trigger_id
}

output "feature_branch_trigger_name" {
  description = "The name of the feature branch Cloud Build trigger"
  value       = google_cloudbuild_trigger.feature_branch_trigger.name
}

# Service Account Information
output "build_service_account_email" {
  description = "The email address of the Cloud Build service account"
  value       = google_service_account.build_service_account.email
}

output "build_service_account_name" {
  description = "The name of the Cloud Build service account"
  value       = google_service_account.build_service_account.name
}

output "build_service_account_unique_id" {
  description = "The unique ID of the Cloud Build service account"
  value       = google_service_account.build_service_account.unique_id
}

# Storage Configuration
output "build_artifacts_bucket_name" {
  description = "The name of the build artifacts storage bucket"
  value       = google_storage_bucket.build_artifacts.name
}

output "build_artifacts_bucket_url" {
  description = "The URL of the build artifacts storage bucket"
  value       = google_storage_bucket.build_artifacts.url
}

output "build_artifacts_bucket_self_link" {
  description = "The self link of the build artifacts storage bucket"
  value       = google_storage_bucket.build_artifacts.self_link
}

# Artifact Registry Information
output "artifact_registry_repository_name" {
  description = "The name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.mobile_images.name
}

output "artifact_registry_repository_id" {
  description = "The ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.mobile_images.repository_id
}

output "artifact_registry_repository_location" {
  description = "The location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.mobile_images.location
}

# Notification Configuration
output "build_notifications_topic_name" {
  description = "The name of the build notifications Pub/Sub topic"
  value       = var.enable_build_notifications ? google_pubsub_topic.build_notifications[0].name : null
}

output "build_notifications_topic_id" {
  description = "The ID of the build notifications Pub/Sub topic"
  value       = var.enable_build_notifications ? google_pubsub_topic.build_notifications[0].id : null
}

# Secret Manager Information
output "firebase_service_account_secret_name" {
  description = "The name of the Firebase service account secret in Secret Manager"
  value       = google_secret_manager_secret.firebase_service_account.secret_id
}

output "firebase_service_account_secret_id" {
  description = "The ID of the Firebase service account secret in Secret Manager"
  value       = google_secret_manager_secret.firebase_service_account.id
}

# Binary Authorization Configuration (if enabled)
output "binary_authorization_policy_name" {
  description = "The name of the Binary Authorization policy"
  value       = var.enable_binary_authorization ? google_binary_authorization_policy.mobile_policy[0].name : null
}

output "binary_authorization_attestor_name" {
  description = "The name of the Binary Authorization attestor"
  value       = var.enable_binary_authorization ? google_binary_authorization_attestor.build_attestor[0].name : null
}

# Test Configuration Information
output "test_devices_configuration" {
  description = "The configured test devices for Firebase Test Lab"
  value       = var.test_devices
}

output "tester_groups_configuration" {
  description = "The configured tester groups for Firebase App Distribution"
  value       = var.tester_groups
}

# Resource Names with Unique Suffix
output "unique_resource_suffix" {
  description = "The unique suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Build Substitution Variables
output "build_substitutions" {
  description = "The substitution variables available for Cloud Build"
  value = {
    android_app_id     = google_firebase_android_app.android_app.app_id
    ios_app_id        = google_firebase_ios_app.ios_app.app_id
    project_id        = var.project_id
    artifact_bucket   = google_storage_bucket.build_artifacts.name
    environment       = var.environment
    notification_topic = var.enable_build_notifications ? google_pubsub_topic.build_notifications[0].name : ""
  }
}

# CLI Commands for Setup
output "setup_commands" {
  description = "Useful CLI commands for setting up the mobile CI/CD pipeline"
  value = {
    clone_repository = "gcloud source repos clone ${google_sourcerepo_repository.mobile_repo.name} --project=${var.project_id}"
    trigger_build    = "gcloud builds triggers run ${google_cloudbuild_trigger.main_branch_trigger.name} --branch=main --project=${var.project_id}"
    list_builds      = "gcloud builds list --project=${var.project_id}"
    view_logs        = "gcloud builds log <BUILD-ID> --project=${var.project_id}"
  }
}

# Firebase CLI Commands
output "firebase_commands" {
  description = "Useful Firebase CLI commands for app distribution"
  value = {
    login           = "firebase login"
    use_project     = "firebase use ${google_firebase_project.mobile_project.project}"
    list_apps       = "firebase apps:list --project=${google_firebase_project.mobile_project.project}"
    create_groups   = "firebase appdistribution:group:create qa-team --project=${google_firebase_project.mobile_project.project}"
    add_testers     = "firebase appdistribution:testers:add tester@example.com --group qa-team --project=${google_firebase_project.mobile_project.project}"
    list_releases   = "firebase appdistribution:releases:list --app=${google_firebase_android_app.android_app.app_id} --project=${google_firebase_project.mobile_project.project}"
  }
}

# URLs and Links
output "console_links" {
  description = "Direct links to Google Cloud Console for created resources"
  value = {
    firebase_console     = "https://console.firebase.google.com/project/${google_firebase_project.mobile_project.project}"
    cloud_build_console  = "https://console.cloud.google.com/cloud-build/dashboard?project=${var.project_id}"
    source_repo_console  = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    storage_console      = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.build_artifacts.name}?project=${var.project_id}"
    app_distribution    = "https://console.firebase.google.com/project/${google_firebase_project.mobile_project.project}/appdistribution"
    test_lab_console    = "https://console.firebase.google.com/project/${google_firebase_project.mobile_project.project}/testlab/histories"
  }
}

# Security Information
output "security_recommendations" {
  description = "Security recommendations for the mobile CI/CD pipeline"
  value = {
    service_account_key_rotation = "Rotate service account keys regularly using: gcloud iam service-accounts keys create --iam-account=${google_service_account.build_service_account.email}"
    secret_rotation             = "Update Firebase service account secret in Secret Manager regularly"
    iam_audit                   = "Regularly audit IAM permissions using: gcloud projects get-iam-policy ${var.project_id}"
    vulnerability_scanning      = "Enable vulnerability scanning: gcloud container images scan <IMAGE-URL>"
    binary_authorization        = var.enable_binary_authorization ? "Binary Authorization is enabled" : "Consider enabling Binary Authorization for additional security"
  }
}