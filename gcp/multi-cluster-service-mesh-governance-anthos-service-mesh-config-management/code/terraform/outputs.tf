# Project and resource identification outputs
output "project_id" {
  description = "Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where zonal resources were deployed"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Network infrastructure outputs
output "network_name" {
  description = "Name of the VPC network created for the service mesh clusters"
  value       = google_compute_network.service_mesh_network.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.service_mesh_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet created for the clusters"
  value       = google_compute_subnetwork.service_mesh_subnet.name
}

output "subnet_self_link" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.service_mesh_subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.service_mesh_subnet.ip_cidr_range
}

output "pods_cidr" {
  description = "CIDR range for pods"
  value       = var.pods_cidr
}

output "services_cidr" {
  description = "CIDR range for services"
  value       = var.services_cidr
}

# GKE cluster outputs
output "cluster_names" {
  description = "Names of all GKE clusters created"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.name }
}

output "cluster_endpoints" {
  description = "Endpoint URLs for all GKE clusters"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.endpoint }
  sensitive   = true
}

output "cluster_ca_certificates" {
  description = "CA certificates for all GKE clusters"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.master_auth[0].cluster_ca_certificate }
  sensitive   = true
}

output "cluster_locations" {
  description = "Locations of all GKE clusters"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.location }
}

output "cluster_zones" {
  description = "Zones of all GKE clusters"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.node_locations }
}

output "cluster_versions" {
  description = "Kubernetes versions of all GKE clusters"
  value       = { for k, v in google_container_cluster.service_mesh_clusters : k => v.master_version }
}

# kubectl connection commands
output "kubectl_connection_commands" {
  description = "Commands to connect kubectl to each cluster"
  value = {
    for k, v in google_container_cluster.service_mesh_clusters :
    k => "gcloud container clusters get-credentials ${v.name} --zone=${v.location} --project=${var.project_id}"
  }
}

# GKE Hub and Fleet Management outputs
output "hub_membership_ids" {
  description = "GKE Hub membership IDs for all clusters"
  value       = { for k, v in google_gke_hub_membership.cluster_memberships : k => v.membership_id }
}

output "hub_membership_names" {
  description = "GKE Hub membership names for all clusters"
  value       = { for k, v in google_gke_hub_membership.cluster_memberships : k => v.name }
}

# Service Mesh outputs
output "service_mesh_enabled" {
  description = "Whether Anthos Service Mesh is enabled"
  value       = var.enable_anthos_service_mesh
}

output "service_mesh_feature_name" {
  description = "Name of the Service Mesh feature in GKE Hub"
  value       = var.enable_anthos_service_mesh ? google_gke_hub_feature.service_mesh[0].name : null
}

output "service_mesh_release_channel" {
  description = "Release channel configured for Anthos Service Mesh"
  value       = var.service_mesh_release_channel
}

# Config Management outputs
output "config_management_enabled" {
  description = "Whether Anthos Config Management is enabled"
  value       = var.enable_config_management
}

output "config_management_feature_name" {
  description = "Name of the Config Management feature in GKE Hub"
  value       = var.enable_config_management ? google_gke_hub_feature.config_management[0].name : null
}

output "config_sync_repository" {
  description = "Git repository URL configured for Config Management synchronization"
  value = var.config_sync_git_repo != "" ? var.config_sync_git_repo : (
    var.enable_config_management && length(google_sourcerepo_repository.config_management_repo) > 0 ?
    "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.config_management_repo[0].name}" :
    null
  )
}

output "config_sync_branch" {
  description = "Git branch configured for Config Management synchronization"
  value       = var.config_sync_git_branch
}

output "config_sync_policy_dir" {
  description = "Policy directory configured for Config Management"
  value       = var.config_sync_policy_dir
}

# Binary Authorization outputs
output "binary_authorization_enabled" {
  description = "Whether Binary Authorization is enabled"
  value       = var.enable_binary_authorization
}

output "binary_authorization_policy_name" {
  description = "Name of the Binary Authorization policy"
  value       = var.enable_binary_authorization ? google_binary_authorization_policy.policy[0].name : null
}

output "attestor_names" {
  description = "Names of Binary Authorization attestors for each environment"
  value       = var.enable_binary_authorization ? { for k, v in google_binary_authorization_attestor.attestors : k => v.name } : {}
}

output "container_analysis_note_names" {
  description = "Names of Container Analysis notes for each environment"
  value       = var.enable_binary_authorization ? { for k, v in google_container_analysis_note.attestor_notes : k => v.name } : {}
}

# Artifact Registry outputs
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  value       = var.enable_binary_authorization && length(google_artifact_registry_repository.secure_apps) > 0 ? google_artifact_registry_repository.secure_apps[0].name : null
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value = var.enable_binary_authorization && length(google_artifact_registry_repository.secure_apps) > 0 ? (
    "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_apps[0].repository_id}"
  ) : null
}

# Service Account outputs
output "gke_node_service_account_email" {
  description = "Email of the service account used by GKE nodes"
  value       = google_service_account.gke_nodes.email
}

output "gke_node_service_account_name" {
  description = "Name of the service account used by GKE nodes"
  value       = google_service_account.gke_nodes.name
}

# Monitoring and Logging outputs
output "monitoring_enabled" {
  description = "Whether Google Cloud Monitoring is enabled"
  value       = var.enable_monitoring
}

output "logging_enabled" {
  description = "Whether Google Cloud Logging is enabled"
  value       = var.enable_logging
}

output "monitoring_dashboard_url" {
  description = "URL of the Service Mesh monitoring dashboard"
  value = var.enable_monitoring && length(google_monitoring_dashboard.service_mesh_dashboard) > 0 ? (
    "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.service_mesh_dashboard[0].id}?project=${var.project_id}"
  ) : null
}

output "log_bucket_name" {
  description = "Name of the Cloud Storage bucket for log storage"
  value       = var.enable_logging && length(google_storage_bucket.log_bucket) > 0 ? google_storage_bucket.log_bucket[0].name : null
}

output "log_bucket_url" {
  description = "URL of the Cloud Storage bucket for log storage"
  value       = var.enable_logging && length(google_storage_bucket.log_bucket) > 0 ? google_storage_bucket.log_bucket[0].url : null
}

# Security and compliance outputs
output "workload_identity_enabled" {
  description = "Whether Workload Identity is enabled on clusters"
  value       = var.enable_workload_identity
}

output "network_policy_enabled" {
  description = "Whether network policy enforcement is enabled"
  value       = var.enable_network_policy
}

output "pod_security_policy_enabled" {
  description = "Whether Pod Security Policy is enabled"
  value       = var.enable_pod_security_policy
}

output "private_clusters_enabled" {
  description = "Whether clusters are configured as private clusters"
  value       = true
}

# Resource naming and labels outputs
output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Fleet management verification outputs
output "fleet_verification_commands" {
  description = "Commands to verify fleet membership and service mesh status"
  value = {
    list_memberships = "gcloud container fleet memberships list --project=${var.project_id}"
    describe_mesh    = "gcloud container fleet mesh describe --project=${var.project_id}"
    list_features    = "gcloud container fleet features list --project=${var.project_id}"
  }
}

# Service mesh validation outputs
output "service_mesh_validation_commands" {
  description = "Commands to validate service mesh deployment on each cluster"
  value = {
    for k, v in google_container_cluster.service_mesh_clusters :
    k => {
      get_credentials = "gcloud container clusters get-credentials ${v.name} --zone=${v.location} --project=${var.project_id}"
      check_istio_pods = "kubectl get pods -n istio-system"
      check_gateways   = "kubectl get gateways -A"
      check_vs         = "kubectl get virtualservices -A"
      check_dr         = "kubectl get destinationrules -A"
      check_pa         = "kubectl get peerauthentication -A"
      check_ap         = "kubectl get authorizationpolicy -A"
    }
  }
}

# Config Management validation outputs
output "config_management_validation_commands" {
  description = "Commands to validate Config Management status on each cluster"
  value = var.enable_config_management ? {
    for k, v in google_container_cluster.service_mesh_clusters :
    k => {
      get_credentials    = "gcloud container clusters get-credentials ${v.name} --zone=${v.location} --project=${var.project_id}"
      check_config_mgmt  = "kubectl get configmanagement"
      check_sync_status  = "kubectl get reposync -n config-management-system"
      check_policy_ctrl  = "kubectl get constraints"
      check_namespaces   = "kubectl get namespaces --show-labels"
    }
  } : {}
}

# Binary Authorization validation outputs
output "binary_authorization_validation_commands" {
  description = "Commands to validate Binary Authorization configuration"
  value = var.enable_binary_authorization ? {
    export_policy    = "gcloud container binauthz policy export --project=${var.project_id}"
    list_attestors   = "gcloud container binauthz attestors list --project=${var.project_id}"
    list_notes       = "gcloud container analysis notes list --project=${var.project_id}"
    test_deployment  = "kubectl run test-pod --image=nginx --dry-run=server"
  } : {}
}

# Cost optimization information
output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    cluster_autoscaling  = var.enable_cluster_autoscaling
    preemptible_nodes    = var.enable_preemptible_nodes
    node_auto_upgrade    = var.node_auto_upgrade
    node_auto_repair     = var.node_auto_repair
    log_retention_days   = var.log_retention_days
  }
}

# Next steps and important information
output "next_steps" {
  description = "Important next steps after deployment"
  value = [
    "1. Configure kubectl for each cluster using the connection commands provided",
    "2. Set up Git repository for Config Management if not already configured",
    "3. Create and push initial configuration policies to the Config Management repository",
    "4. Verify service mesh installation using the validation commands",
    "5. Deploy sample applications to test service mesh functionality",
    "6. Configure monitoring alerts and notification channels",
    "7. Set up Binary Authorization attestors and signing processes for production use",
    "8. Review and customize security policies for your organization's requirements"
  ]
}

# Important security notices
output "security_notices" {
  description = "Important security considerations and notices"
  value = [
    "WARNING: Default authorized networks allow access from any IP (0.0.0.0/0). Restrict this in production.",
    "NOTICE: Binary Authorization is configured with example attestors. Configure proper signing processes for production.",
    "NOTICE: Private clusters are enabled for enhanced security.",
    "NOTICE: Workload Identity is enabled for secure pod-to-Google Cloud service authentication.",
    "NOTICE: Network policies are enabled for additional network security.",
    "NOTICE: All inter-service communication will be encrypted with mutual TLS when properly configured."
  ]
}