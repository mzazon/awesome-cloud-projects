# Project and Environment Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where resources were created"
  value       = var.zone
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Artifact Registry Outputs
output "artifact_registry_repository_name" {
  description = "The name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_images.name
}

output "artifact_registry_repository_id" {
  description = "The full repository ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_images.id
}

output "artifact_registry_repository_url" {
  description = "The URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_images.name}"
}

output "docker_push_command" {
  description = "Example command to push an image to the Artifact Registry repository"
  value       = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_images.name}/your-image:tag"
}

# GKE Cluster Outputs
output "gke_cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.secure_cluster.name
}

output "gke_cluster_id" {
  description = "The full cluster ID"
  value       = google_container_cluster.secure_cluster.id
}

output "gke_cluster_endpoint" {
  description = "The endpoint of the GKE cluster"
  value       = google_container_cluster.secure_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "The CA certificate of the GKE cluster"
  value       = google_container_cluster.secure_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.secure_cluster.name} --zone ${var.zone} --project ${var.project_id}"
}

# Cloud KMS Outputs
output "kms_keyring_name" {
  description = "The name of the Cloud KMS keyring"
  value       = google_kms_key_ring.attestor_keyring.name
}

output "kms_keyring_id" {
  description = "The full ID of the Cloud KMS keyring"
  value       = google_kms_key_ring.attestor_keyring.id
}

output "kms_key_name" {
  description = "The name of the Cloud KMS key"
  value       = google_kms_crypto_key.attestor_key.name
}

output "kms_key_id" {
  description = "The full ID of the Cloud KMS key"
  value       = google_kms_crypto_key.attestor_key.id
}

output "kms_key_version_id" {
  description = "The current version ID of the Cloud KMS key"
  value       = data.google_kms_crypto_key_version.attestor_key_version.id
}

# Binary Authorization Outputs
output "binary_authorization_attestor_name" {
  description = "The name of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.build_attestor.name
}

output "binary_authorization_attestor_id" {
  description = "The full ID of the Binary Authorization attestor"
  value       = google_binary_authorization_attestor.build_attestor.id
}

output "container_analysis_note_name" {
  description = "The name of the Container Analysis note"
  value       = google_container_analysis_note.attestor_note.name
}

output "binary_authorization_policy_status" {
  description = "Binary Authorization policy enforcement status"
  value       = "Binary Authorization is enabled with ${var.binary_authorization_policy_mode} enforcement mode"
}

# Network Outputs
output "vpc_network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.secure_network.name
}

output "vpc_network_id" {
  description = "The full ID of the VPC network"
  value       = google_compute_network.secure_network.id
}

output "subnet_name" {
  description = "The name of the subnet"
  value       = google_compute_subnetwork.secure_subnet.name
}

output "subnet_id" {
  description = "The full ID of the subnet"
  value       = google_compute_subnetwork.secure_subnet.id
}

output "subnet_cidr" {
  description = "The CIDR block of the subnet"
  value       = google_compute_subnetwork.secure_subnet.ip_cidr_range
}

# Cloud Build Outputs
output "cloud_build_trigger_name" {
  description = "The name of the Cloud Build trigger (if enabled)"
  value       = var.enable_cloud_build_trigger ? google_cloudbuild_trigger.secure_build_trigger[0].name : null
}

output "cloud_build_trigger_id" {
  description = "The ID of the Cloud Build trigger (if enabled)"
  value       = var.enable_cloud_build_trigger ? google_cloudbuild_trigger.secure_build_trigger[0].id : null
}

output "source_repository_name" {
  description = "The name of the source repository (if enabled)"
  value       = var.enable_cloud_build_trigger ? google_sourcerepo_repository.secure_app_repo[0].name : null
}

output "source_repository_url" {
  description = "The URL of the source repository (if enabled)"
  value       = var.enable_cloud_build_trigger ? google_sourcerepo_repository.secure_app_repo[0].url : null
}

output "cloud_build_service_account" {
  description = "The Cloud Build service account email"
  value       = local.cloud_build_sa
}

# Security Information
output "security_summary" {
  description = "Summary of security configurations"
  value = {
    binary_authorization_enabled = var.enable_binary_authorization
    vulnerability_scanning       = var.enable_vulnerability_scanning
    private_gke_nodes           = var.enable_private_nodes
    network_policy_enabled      = var.enable_network_policy
    shielded_nodes_enabled      = true
    workload_identity_enabled   = true
    kms_protection_level        = var.kms_key_protection_level
    enforcement_mode            = var.binary_authorization_policy_mode
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Commands to deploy and manage the infrastructure"
  value = {
    configure_docker_auth = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    get_cluster_credentials = "gcloud container clusters get-credentials ${google_container_cluster.secure_cluster.name} --zone ${var.zone} --project ${var.project_id}"
    build_sample_image = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_images.name}/sample-app:latest ."
    push_sample_image = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_images.name}/sample-app:latest"
    create_attestation = "gcloud container binauthz attestations sign-and-create --artifact-url=${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_images.name}/sample-app:latest --attestor=${google_binary_authorization_attestor.build_attestor.name} --attestor-project=${var.project_id} --keyversion-project=${var.project_id} --keyversion-location=${var.region} --keyversion-keyring=${google_kms_key_ring.attestor_keyring.name} --keyversion-key=${google_kms_crypto_key.attestor_key.name} --keyversion=1"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_binary_authorization_policy = "gcloud container binauthz policy export"
    list_attestors = "gcloud container binauthz attestors list"
    describe_attestor = "gcloud container binauthz attestors describe ${google_binary_authorization_attestor.build_attestor.name}"
    check_cluster_binary_authorization = "gcloud container clusters describe ${google_container_cluster.secure_cluster.name} --zone ${var.zone} --format='value(binaryAuthorization.enabled)'"
    list_repositories = "gcloud artifacts repositories list --location=${var.region}"
    scan_image = "gcloud artifacts docker images scan [IMAGE_URL] --location=${var.region}"
  }
}

# Monitoring and Logging
output "monitoring_dashboards" {
  description = "Links to monitoring dashboards"
  value = {
    gke_dashboard = "https://console.cloud.google.com/kubernetes/clusters/details/${var.zone}/${google_container_cluster.secure_cluster.name}/overview?project=${var.project_id}"
    binary_authorization_dashboard = "https://console.cloud.google.com/security/binary-authorization/policy?project=${var.project_id}"
    artifact_registry_dashboard = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.secure_images.name}?project=${var.project_id}"
    cloud_build_dashboard = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    kms_dashboard = "https://console.cloud.google.com/security/kms/keyring/manage/${var.region}/${google_kms_key_ring.attestor_keyring.name}?project=${var.project_id}"
  }
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs for the resources (approximate)"
  value = {
    note = "Costs are approximate and depend on usage patterns"
    gke_cluster = "~$73/month for e2-medium nodes (1-3 nodes)"
    artifact_registry = "~$0.10/GB/month for storage"
    cloud_kms = "~$1/month per key + $0.03 per 10,000 operations"
    cloud_build = "~$0.003/build minute (first 120 minutes/day free)"
    networking = "~$0.10/GB for NAT gateway + standard networking charges"
    total_estimated = "~$80-100/month for typical development usage"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure kubectl to connect to the cluster using the provided command",
    "2. Set up Docker authentication for Artifact Registry",
    "3. Create a sample application with Dockerfile",
    "4. Push the application to Artifact Registry",
    "5. Create an attestation for the image",
    "6. Deploy the attested image to the GKE cluster",
    "7. Test Binary Authorization by attempting to deploy an unattested image",
    "8. Set up monitoring and alerting for Binary Authorization policy violations",
    "9. Configure Cloud Build triggers for automated CI/CD pipeline",
    "10. Review and customize the Binary Authorization policy as needed"
  ]
}