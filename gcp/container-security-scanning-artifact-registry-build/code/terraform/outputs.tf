# Project and location outputs
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone"
  value       = var.zone
}

# Artifact Registry outputs
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_repo.name
}

output "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_repo.id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_repo.name}"
}

output "docker_push_command" {
  description = "Docker command to push images to the repository"
  value       = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_repo.name}/IMAGE_NAME:TAG"
}

# GKE cluster outputs
output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.security_cluster.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.security_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "CA certificate of the GKE cluster"
  value       = google_container_cluster.security_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.security_cluster.name} --zone=${var.zone} --project=${var.project_id}"
}

# Service account outputs
output "security_service_account_email" {
  description = "Email address of the security service account"
  value       = google_service_account.security_scanner.email
}

output "security_service_account_id" {
  description = "ID of the security service account"
  value       = google_service_account.security_scanner.id
}

output "cloud_build_service_account_email" {
  description = "Email address of the Cloud Build service account"
  value       = data.google_project.current.number != null ? "${data.google_project.current.number}@cloudbuild.gserviceaccount.com" : "Cloud Build service account not found"
}

# Binary Authorization outputs
output "attestor_name" {
  description = "Name of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.security_attestor.name
}

output "attestor_id" {
  description = "ID of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.security_attestor.id
}

output "container_analysis_note_name" {
  description = "Name of the Container Analysis note"
  value       = google_container_analysis_note.attestor_note.name
}

# KMS outputs
output "kms_keyring_name" {
  description = "Name of the KMS keyring"
  value       = google_kms_key_ring.security_keyring.name
}

output "kms_key_name" {
  description = "Name of the KMS signing key"
  value       = google_kms_crypto_key.security_signing_key.name
}

output "kms_key_id" {
  description = "ID of the KMS signing key"
  value       = google_kms_crypto_key.security_signing_key.id
}

# Network outputs
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc_network.name
}

output "vpc_subnet_name" {
  description = "Name of the VPC subnet"
  value       = google_compute_subnetwork.vpc_subnet.name
}

output "vpc_subnet_cidr" {
  description = "CIDR range of the VPC subnet"
  value       = google_compute_subnetwork.vpc_subnet.ip_cidr_range
}

# Security and monitoring outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com"
  ]
}

output "security_policy_summary" {
  description = "Summary of the configured security policy"
  value = {
    max_critical_vulnerabilities = var.vulnerability_policy.max_critical_vulnerabilities
    max_high_vulnerabilities     = var.vulnerability_policy.max_high_vulnerabilities
    scan_timeout_minutes         = var.vulnerability_policy.scan_timeout_minutes
    binary_authorization_enabled = true
    vulnerability_scanning_enabled = true
  }
}

# Cloud Build integration outputs
output "cloud_build_trigger_instructions" {
  description = "Instructions for setting up Cloud Build triggers"
  value = {
    repository_url = "Connect your source repository (GitHub, Cloud Source Repositories, etc.)"
    build_config_file = "cloudbuild.yaml"
    service_account = google_service_account.security_scanner.email
    substitution_variables = {
      "_REGION" = var.region
      "_PROJECT_ID" = var.project_id
      "_REPO_NAME" = google_artifact_registry_repository.secure_repo.name
      "_ATTESTOR_NAME" = google_binary_authorization_attestor.security_attestor.name
      "_KMS_KEY_NAME" = google_kms_crypto_key.security_signing_key.name
      "_KMS_KEYRING_NAME" = google_kms_key_ring.security_keyring.name
    }
  }
}

# Validation and testing outputs
output "vulnerability_scan_command" {
  description = "Command to manually trigger vulnerability scanning"
  value = "gcloud artifacts docker images scan ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_repo.name}/IMAGE_NAME:TAG"
}

output "binary_authorization_test_commands" {
  description = "Commands to test Binary Authorization enforcement"
  value = {
    deploy_attested_image = "kubectl create deployment test-app --image=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_repo.name}/IMAGE_NAME:TAG"
    deploy_unauthorized_image = "kubectl create deployment unauthorized-app --image=nginx:latest"
    check_policy = "gcloud container binauthz policy export"
  }
}

# Security monitoring outputs
output "security_command_center_url" {
  description = "URL to view Security Command Center findings"
  value = var.enable_security_command_center ? "https://console.cloud.google.com/security/command-center/findings?project=${var.project_id}" : "Security Command Center integration disabled"
}

output "container_analysis_url" {
  description = "URL to view Container Analysis results"
  value = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.secure_repo.name}?project=${var.project_id}"
}

# Cleanup instructions
output "cleanup_instructions" {
  description = "Instructions for cleaning up resources"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup_required = [
      "Container images in Artifact Registry (if not managed by Terraform)",
      "Cloud Build history and logs",
      "Security Command Center findings history"
    ]
    verification_commands = [
      "gcloud artifacts repositories list --location=${var.region}",
      "gcloud container clusters list --zone=${var.zone}",
      "gcloud kms keyrings list --location=${var.region}",
      "gcloud container binauthz attestors list"
    ]
  }
}