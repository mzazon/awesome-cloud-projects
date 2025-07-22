# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are located"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Cloud Source Repository outputs
output "repository_name" {
  description = "Name of the created Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.name
}

output "repository_url" {
  description = "HTTPS clone URL for the Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.url
}

output "repository_clone_command" {
  description = "Command to clone the Cloud Source Repository"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.app_repo.name} --project=${var.project_id}"
}

# Cloud Build outputs
output "build_service_account_email" {
  description = "Email address of the Cloud Build service account"
  value       = google_service_account.build_service_account.email
}

output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.security_trigger.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.security_trigger.trigger_id
}

output "container_image_url" {
  description = "Base URL for container images in Google Container Registry"
  value       = "gcr.io/${var.project_id}/${var.container_image_name}"
}

# Binary Authorization outputs
output "attestor_name" {
  description = "Name of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.quality_attestor.name
}

output "attestor_resource_name" {
  description = "Full resource name of the Binary Authorization attestor"
  value       = "projects/${var.project_id}/attestors/${google_binary_authorization_attestor.quality_attestor.name}"
}

output "kms_key_ring_name" {
  description = "Name of the KMS key ring used for attestation"
  value       = google_kms_key_ring.binauthz_keyring.name
}

output "kms_crypto_key_name" {
  description = "Name of the KMS crypto key used for attestation signing"
  value       = google_kms_crypto_key.attestor_key.name
}

output "kms_key_version_resource_name" {
  description = "Full resource name of the KMS key version for attestation"
  value       = "${google_kms_crypto_key.attestor_key.id}/cryptoKeyVersions/1"
}

# GKE cluster outputs
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.security_cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the GKE cluster"
  value       = google_container_cluster.security_cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster"
  value       = google_container_cluster.security_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location (zone) of the GKE cluster"
  value       = google_container_cluster.security_cluster.location
}

output "get_credentials_command" {
  description = "Command to get kubectl credentials for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.security_cluster.name} --zone=${google_container_cluster.security_cluster.location} --project=${var.project_id}"
}

output "node_pool_name" {
  description = "Name of the GKE node pool"
  value       = google_container_node_pool.security_nodes.name
}

# Security Command Center outputs
output "scc_source_name" {
  description = "Name of the Security Command Center source"
  value       = google_scc_source.pipeline_source.name
}

output "scc_source_resource_name" {
  description = "Full resource name of the Security Command Center source"
  value       = google_scc_source.pipeline_source.name
}

output "sample_finding_name" {
  description = "Name of the sample security finding created"
  value       = google_scc_finding.sample_finding.parent
}

# Security and compliance information
output "binauthz_policy_status" {
  description = "Status information about Binary Authorization policy"
  value = {
    enforcement_mode = var.binauthz_policy_enforcement_mode
    attestor_required = google_binary_authorization_attestor.quality_attestor.name
    policy_enabled = true
  }
}

# URLs for Google Cloud Console access
output "console_urls" {
  description = "URLs for accessing resources in Google Cloud Console"
  value = {
    cloud_build_triggers = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
    container_registry = "https://console.cloud.google.com/gcr/images/${var.project_id}?project=${var.project_id}"
    gke_clusters = "https://console.cloud.google.com/kubernetes/list/overview?project=${var.project_id}"
    binary_authorization = "https://console.cloud.google.com/security/binary-authorization/attestors?project=${var.project_id}"
    security_command_center = "https://console.cloud.google.com/security/command-center/findings?project=${var.project_id}"
    source_repositories = "https://console.cloud.google.com/code/develop/browse/${google_sourcerepo_repository.app_repo.name}?project=${var.project_id}"
  }
}

# Development workflow commands
output "development_commands" {
  description = "Common commands for development workflow"
  value = {
    clone_repository = "gcloud source repos clone ${google_sourcerepo_repository.app_repo.name} --project=${var.project_id}"
    trigger_build = "gcloud builds triggers run ${google_cloudbuild_trigger.security_trigger.name} --branch=main --project=${var.project_id}"
    list_builds = "gcloud builds list --project=${var.project_id} --limit=10"
    list_images = "gcloud container images list --repository=gcr.io/${var.project_id} --project=${var.project_id}"
    check_attestations = "gcloud container binauthz attestations list --attestor=${google_binary_authorization_attestor.quality_attestor.name} --project=${var.project_id}"
    view_scc_findings = "gcloud scc findings list --source=${google_scc_source.pipeline_source.name}"
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for created resources"
  value = {
    note = "Costs may vary based on usage patterns and regional pricing"
    gke_cluster = "~$75-150/month (depends on node utilization)"
    cloud_build = "~$5-20/month (120 free build minutes per day)"
    container_registry = "~$5-15/month (depends on image storage)"
    kms_operations = "~$1-5/month (key operations)"
    total_estimated = "~$86-190/month"
    free_tier_note = "Some services have free tier allowances that may reduce actual costs"
  }
}

# Security compliance status
output "security_features_enabled" {
  description = "Summary of security features enabled in this deployment"
  value = {
    binary_authorization = true
    container_vulnerability_scanning = var.enable_container_scanning
    shielded_gke_nodes = var.enable_shielded_nodes
    network_policies = var.enable_network_policy
    workload_identity = var.enable_workload_identity
    private_cluster = true
    security_command_center_integration = true
    automated_security_scanning = true
  }
}