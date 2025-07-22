# outputs.tf
# Output values for GCP multiplayer gaming infrastructure

# Project and Region Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were deployed"
  value       = var.zone
}

# Network Infrastructure
output "network_name" {
  description = "Name of the VPC network created for gaming infrastructure"
  value       = google_compute_network.gaming_network.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.gaming_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet created for GKE cluster"
  value       = google_compute_subnetwork.gaming_subnet.name
}

output "subnet_self_link" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.gaming_subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.gaming_subnet.ip_cidr_range
}

# GKE Cluster Information
output "gke_cluster_name" {
  description = "Name of the GKE cluster for game servers"
  value       = google_container_cluster.game_cluster.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint for the GKE cluster"
  value       = google_container_cluster.game_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "CA certificate for the GKE cluster"
  value       = google_container_cluster.game_cluster.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.game_cluster.location
}

output "gke_cluster_self_link" {
  description = "Self-link of the GKE cluster"
  value       = google_container_cluster.game_cluster.self_link
}

output "gke_node_pool_name" {
  description = "Name of the GKE node pool"
  value       = google_container_node_pool.game_nodes.name
}

output "gke_nodes_service_account" {
  description = "Service account email for GKE nodes"
  value       = google_service_account.gke_nodes.email
}

# Agones Game Server Information
output "agones_namespace" {
  description = "Kubernetes namespace where Agones is installed"
  value       = helm_release.agones.namespace
}

output "agones_version" {
  description = "Version of Agones installed"
  value       = helm_release.agones.version
}

output "game_server_namespace" {
  description = "Kubernetes namespace for game servers"
  value       = kubernetes_namespace.game_servers.metadata[0].name
}

output "game_server_fleet_name" {
  description = "Name of the game server fleet"
  value       = "simple-game-server-fleet"
}

output "game_server_port_range" {
  description = "Port range configured for game servers"
  value       = "${var.agones_gameserver_min_port}-${var.agones_gameserver_max_port}"
}

# Cloud Firestore Information
output "firestore_database_name" {
  description = "Name of the Cloud Firestore database"
  value       = google_firestore_database.game_database.name
}

output "firestore_database_location" {
  description = "Location of the Cloud Firestore database"
  value       = google_firestore_database.game_database.location_id
}

output "firestore_database_type" {
  description = "Type of the Cloud Firestore database"
  value       = google_firestore_database.game_database.type
}

# Cloud Run Service Information
output "cloud_run_service_name" {
  description = "Name of the Cloud Run matchmaking service"
  value       = google_cloud_run_service.matchmaking_service.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run matchmaking service"
  value       = google_cloud_run_service.matchmaking_service.status[0].url
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_service.matchmaking_service.location
}

output "cloud_run_service_account" {
  description = "Service account email for Cloud Run service"
  value       = google_service_account.cloud_run_sa.email
}

# Load Balancer Information (if enabled)
output "load_balancer_ip" {
  description = "IP address of the global load balancer (if enabled)"
  value = var.enable_global_load_balancer ? (
    var.enable_ssl ? 
    google_compute_global_forwarding_rule.game_https_forwarding_rule[0].ip_address :
    google_compute_global_forwarding_rule.game_forwarding_rule[0].ip_address
  ) : null
}

output "load_balancer_url" {
  description = "URL of the global load balancer (if enabled)"
  value = var.enable_global_load_balancer ? (
    var.enable_ssl ? 
    "https://${google_compute_global_forwarding_rule.game_https_forwarding_rule[0].ip_address}" :
    "http://${google_compute_global_forwarding_rule.game_forwarding_rule[0].ip_address}"
  ) : null
}

output "backend_service_name" {
  description = "Name of the backend service (if load balancer is enabled)"
  value       = var.enable_global_load_balancer ? google_compute_backend_service.game_backend[0].name : null
}

output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (if SSL is enabled)"
  value       = var.enable_global_load_balancer && var.enable_ssl ? google_compute_managed_ssl_certificate.game_ssl[0].name : null
}

# Access Information for kubectl
output "kubectl_config_command" {
  description = "Command to configure kubectl for the GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.game_cluster.name} --zone ${google_container_cluster.game_cluster.location} --project ${var.project_id}"
}

# Monitoring and Management URLs
output "gke_cluster_dashboard_url" {
  description = "URL to view the GKE cluster in Google Cloud Console"
  value       = "https://console.cloud.google.com/kubernetes/clusters/details/${google_container_cluster.game_cluster.location}/${google_container_cluster.game_cluster.name}?project=${var.project_id}"
}

output "cloud_run_dashboard_url" {
  description = "URL to view the Cloud Run service in Google Cloud Console"
  value       = "https://console.cloud.google.com/run/detail/${google_cloud_run_service.matchmaking_service.location}/${google_cloud_run_service.matchmaking_service.name}?project=${var.project_id}"
}

output "firestore_dashboard_url" {
  description = "URL to view the Firestore database in Google Cloud Console"
  value       = "https://console.cloud.google.com/firestore/databases?project=${var.project_id}"
}

output "load_balancer_dashboard_url" {
  description = "URL to view the load balancer in Google Cloud Console (if enabled)"
  value = var.enable_global_load_balancer ? (
    "https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/details/${google_compute_url_map.game_url_map[0].name}?project=${var.project_id}"
  ) : null
}

# Resource Identifiers for External Tools
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Testing and Validation Commands
output "test_matchmaking_command" {
  description = "curl command to test the matchmaking service"
  value = var.enable_global_load_balancer ? (
    "curl -X POST ${var.enable_ssl ? "https" : "http"}://${var.enable_ssl ? google_compute_global_forwarding_rule.game_https_forwarding_rule[0].ip_address : google_compute_global_forwarding_rule.game_forwarding_rule[0].ip_address}/matchmake -H \"Content-Type: application/json\" -d '{\"playerId\": \"test-player\", \"gameMode\": \"battle-royale\"}'"
  ) : (
    "curl -X POST ${google_cloud_run_service.matchmaking_service.status[0].url}/matchmake -H \"Content-Type: application/json\" -d '{\"playerId\": \"test-player\", \"gameMode\": \"battle-royale\"}'"
  )
}

output "check_game_servers_command" {
  description = "kubectl command to check game server status"
  value       = "kubectl get gameservers -n ${kubernetes_namespace.game_servers.metadata[0].name}"
}

output "check_fleet_status_command" {
  description = "kubectl command to check fleet status"
  value       = "kubectl get fleet simple-game-server-fleet -n ${kubernetes_namespace.game_servers.metadata[0].name}"
}

# Environment Variables for Applications
output "environment_variables" {
  description = "Environment variables for applications connecting to this infrastructure"
  value = {
    PROJECT_ID          = var.project_id
    REGION              = var.region
    ZONE                = var.zone
    FIRESTORE_DATABASE  = google_firestore_database.game_database.name
    GKE_CLUSTER_NAME    = google_container_cluster.game_cluster.name
    CLOUD_RUN_URL       = google_cloud_run_service.matchmaking_service.status[0].url
    LOAD_BALANCER_URL   = var.enable_global_load_balancer ? (
      var.enable_ssl ? 
      "https://${google_compute_global_forwarding_rule.game_https_forwarding_rule[0].ip_address}" :
      "http://${google_compute_global_forwarding_rule.game_forwarding_rule[0].ip_address}"
    ) : null
  }
  sensitive = false
}

# Cost Estimation Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs (actual costs may vary)"
  value = {
    gke_cluster    = "GKE cluster with ${var.gke_node_count} ${var.gke_machine_type} nodes"
    cloud_run      = "Cloud Run service with ${var.cloud_run_memory} memory and ${var.cloud_run_cpu} CPU"
    firestore      = "Firestore database with pay-per-usage pricing"
    load_balancer  = var.enable_global_load_balancer ? "Global HTTP(S) Load Balancer with forwarding rules" : "No load balancer"
    note          = "Visit Google Cloud Pricing Calculator for detailed cost estimates"
  }
}