# Project and region information
output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where Compute Engine resources are deployed"
  value       = var.zone
}

# Development VM information
output "dev_vm_name" {
  description = "Name of the development virtual machine"
  value       = google_compute_instance.dev_vm.name
}

output "dev_vm_internal_ip" {
  description = "Internal IP address of the development VM (no external IP for security)"
  value       = google_compute_instance.dev_vm.network_interface[0].network_ip
}

output "dev_vm_zone" {
  description = "Zone where the development VM is deployed"
  value       = google_compute_instance.dev_vm.zone
}

output "dev_vm_machine_type" {
  description = "Machine type of the development VM"
  value       = google_compute_instance.dev_vm.machine_type
}

# Service account information
output "vm_service_account_email" {
  description = "Email of the service account used by the development VM"
  value       = google_service_account.dev_vm_sa.email
}

output "vm_service_account_id" {
  description = "Unique ID of the development VM service account"
  value       = google_service_account.dev_vm_sa.unique_id
}

# Artifact Registry information
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository for container images"
  value       = google_artifact_registry_repository.secure_dev_repo.name
}

output "artifact_registry_repository_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_dev_repo.id
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.secure_dev_repo.location
}

output "docker_registry_url" {
  description = "Docker registry URL for pushing container images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_repo.name}"
}

# IAP access information
output "iap_ssh_command" {
  description = "Command to SSH into the development VM via IAP tunnel"
  value       = "gcloud compute ssh ${google_compute_instance.dev_vm.name} --zone=${google_compute_instance.dev_vm.zone} --tunnel-through-iap"
}

output "iap_port_forward_command" {
  description = "Example command to forward ports through IAP tunnel for development servers"
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.dev_vm.name} 8080 --local-host-port=localhost:8080 --zone=${google_compute_instance.dev_vm.zone}"
}

# Security and access control information
output "firewall_rules" {
  description = "Names of firewall rules created for IAP access"
  value = [
    google_compute_firewall.allow_iap_ssh.name,
    google_compute_firewall.allow_iap_dev_server.name
  ]
}

output "iap_source_ranges" {
  description = "IP ranges used by Identity-Aware Proxy for secure access"
  value       = local.iap_source_ranges
}

# OAuth and IAP configuration
output "oauth_brand_name" {
  description = "Name of the OAuth brand created for IAP (if configured)"
  value       = length(google_iap_brand.dev_environment_brand) > 0 ? google_iap_brand.dev_environment_brand[0].name : "OAuth brand not configured - requires manual setup in Console"
}

output "iap_console_url" {
  description = "URL to configure IAP in Google Cloud Console"
  value       = "https://console.cloud.google.com/security/iap?project=${var.project_id}"
}

# Monitoring and logging information
output "audit_log_sink_name" {
  description = "Name of the Cloud Logging sink for IAP audit logs"
  value       = google_logging_project_sink.iap_audit_sink.name
}

output "monitoring_dashboard_url" {
  description = "URL to view the IAP security monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.iap_security_dashboard.id)[3]}?project=${var.project_id}"
}

# Development environment setup
output "workspace_directory" {
  description = "Development workspace directory on the VM"
  value       = "/home/developer/workspace"
}

output "container_image_uri_template" {
  description = "Template for container image URIs in Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_repo.name}/IMAGE_NAME:TAG"
}

# Cloud Code configuration
output "cloud_code_configuration" {
  description = "Configuration settings for Cloud Code extension"
  value = {
    project_id = var.project_id
    region     = var.region
    artifact_registry_repo = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_repo.name}"
  }
}

# Resource labels and metadata
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming uniqueness"
  value       = local.resource_suffix
}

# Next steps and important information
output "setup_instructions" {
  description = "Next steps to complete the secure development environment setup"
  value = <<-EOT
    1. Configure OAuth consent screen in Cloud Console:
       https://console.cloud.google.com/apis/credentials/consent?project=${var.project_id}
    
    2. Connect to development VM via IAP:
       ${local.vm_name} --zone=${var.zone} --tunnel-through-iap
    
    3. Install Cloud Code extension in VS Code:
       code --install-extension GoogleCloudTools.cloudcode
    
    4. Configure Docker authentication:
       gcloud auth configure-docker ${var.region}-docker.pkg.dev
    
    5. Build and push sample application:
       docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_repo.name}/sample-app:v1.0 .
       docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_repo.name}/sample-app:v1.0
  EOT
}

output "security_notes" {
  description = "Important security information about the deployment"
  value = <<-EOT
    Security Features Enabled:
    - No external IP addresses on development VM
    - Identity-Aware Proxy (IAP) authentication required
    - OS Login enabled for enhanced security (if configured)
    - Artifact Registry with vulnerability scanning
    - Comprehensive audit logging
    - Firewall rules restricting access to IAP source ranges
    - Service account with minimal required permissions
    
    Access Control:
    - Only users granted IAP tunnel access can connect
    - All access attempts are logged and monitored
    - Context-aware access policies can be configured for additional security
  EOT
}