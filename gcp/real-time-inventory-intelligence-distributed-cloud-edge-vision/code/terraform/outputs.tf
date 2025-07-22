# Outputs for Real-Time Inventory Intelligence Infrastructure

# Project Information
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

# Cloud SQL Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL database instance"
  value       = google_sql_database_instance.inventory_db.name
}

output "database_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.inventory_db.connection_name
}

output "database_instance_ip_address" {
  description = "IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.inventory_db.ip_address
  sensitive   = true
}

output "database_name" {
  description = "Name of the inventory database"
  value       = google_sql_database.inventory_database.name
}

output "database_connection_string" {
  description = "Connection string for the inventory database"
  value       = "postgresql://postgres@${google_sql_database_instance.inventory_db.ip_address[0].ip_address}:5432/${google_sql_database.inventory_database.name}"
  sensitive   = true
}

# Cloud Storage Outputs
output "image_bucket_name" {
  description = "Name of the Cloud Storage bucket for images"
  value       = google_storage_bucket.image_bucket.name
}

output "image_bucket_url" {
  description = "URL of the Cloud Storage bucket for images"
  value       = google_storage_bucket.image_bucket.url
}

output "image_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.image_bucket.self_link
}

# GKE Cluster Outputs
output "cluster_name" {
  description = "Name of the GKE edge cluster"
  value       = google_container_cluster.edge_cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.edge_cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate for the GKE cluster"
  value       = google_container_cluster.edge_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.edge_cluster.location
}

output "node_pool_name" {
  description = "Name of the GKE node pool"
  value       = google_container_node_pool.edge_nodes.name
}

# Service Account Outputs
output "edge_processor_service_account_email" {
  description = "Email address of the edge processor service account"
  value       = google_service_account.edge_processor.email
}

output "edge_processor_service_account_unique_id" {
  description = "Unique ID of the edge processor service account"
  value       = google_service_account.edge_processor.unique_id
}

# Kubernetes Deployment Outputs
output "kubernetes_deployment_name" {
  description = "Name of the Kubernetes deployment for inventory processor"
  value       = kubernetes_deployment.inventory_processor.metadata[0].name
}

output "kubernetes_service_name" {
  description = "Name of the Kubernetes service for inventory processor"
  value       = kubernetes_service.inventory_processor_service.metadata[0].name
}

output "kubernetes_service_cluster_ip" {
  description = "Cluster IP of the inventory processor service"
  value       = kubernetes_service.inventory_processor_service.spec[0].cluster_ip
}

# Networking Outputs
output "vpc_network_name" {
  description = "Name of the VPC network (if private networking is enabled)"
  value       = var.enable_private_ip ? google_compute_network.vpc[0].name : null
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network (if private networking is enabled)"
  value       = var.enable_private_ip ? google_compute_network.vpc[0].self_link : null
}

output "subnet_name" {
  description = "Name of the subnet (if private networking is enabled)"
  value       = var.enable_private_ip ? google_compute_subnetwork.subnet[0].name : null
}

output "subnet_cidr_range" {
  description = "CIDR range of the subnet (if private networking is enabled)"
  value       = var.enable_private_ip ? google_compute_subnetwork.subnet[0].ip_cidr_range : null
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the inventory monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.inventory_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the inventory monitoring dashboard"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.inventory_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_id" {
  description = "ID of the low inventory alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.low_inventory_alert[0].name : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
}

# Vision API Outputs
output "vision_api_location" {
  description = "Location configured for Vision API resources"
  value       = var.vision_api_location
}

output "product_set_display_name" {
  description = "Display name of the Vision API product set"
  value       = var.product_set_display_name
}

# Application Configuration Outputs
output "processor_image" {
  description = "Container image used for the inventory processor"
  value       = var.processor_image
}

output "processor_replicas" {
  description = "Number of inventory processor replicas deployed"
  value       = var.processor_replicas
}

# Resource Identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Connection Commands
output "kubectl_connection_command" {
  description = "Command to configure kubectl for the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.edge_cluster.name} --zone=${google_container_cluster.edge_cluster.location} --project=${var.project_id}"
}

output "cloud_sql_proxy_command" {
  description = "Command to start Cloud SQL proxy for local database access"
  value       = "./cloud_sql_proxy -instances=${google_sql_database_instance.inventory_db.connection_name}=tcp:5432"
}

output "gsutil_bucket_command" {
  description = "Command to list contents of the image storage bucket"
  value       = "gsutil ls gs://${google_storage_bucket.image_bucket.name}/"
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    cloud_sql_f1_micro    = "$7-15 (depending on usage)"
    gke_nodes_e2_medium   = "$30-60 (2 nodes)"
    storage_standard      = "$2-5 (depending on usage)"
    vision_api_calls      = "$15-30 (depending on volume)"
    monitoring_logs       = "$5-10 (depending on volume)"
    networking            = "$5-15 (depending on traffic)"
    total_estimated       = "$65-135 per month"
    note                  = "Costs vary based on actual usage patterns and data transfer"
  }
}

# Security Information
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    database_security    = "Rotate database passwords regularly and enable SSL connections"
    workload_identity   = "Workload Identity is ${var.enable_workload_identity ? "enabled" : "disabled"} for secure pod-to-service authentication"
    network_policies    = "Network policies are ${var.enable_network_policy ? "enabled" : "disabled"} for pod-to-pod security"
    private_networking  = "Private networking is ${var.enable_private_ip ? "enabled" : "disabled"} for enhanced security"
    storage_access      = "Storage bucket uses uniform bucket-level access for consistent security"
    monitoring_alerts   = "Configure notification channels to receive security and operational alerts"
  }
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the deployment"
  value = {
    check_cluster_status = "kubectl get nodes && kubectl get pods -n default"
    check_sql_connection = "gcloud sql connect ${google_sql_database_instance.inventory_db.name} --user=postgres"
    check_storage_access = "gsutil ls gs://${google_storage_bucket.image_bucket.name}/"
    check_service_logs   = "kubectl logs -l app=inventory-processor -f"
    check_monitoring     = "gcloud logging read 'resource.type=\"k8s_container\"' --limit 50"
    test_vision_api      = "gcloud ml vision detect-objects gs://path-to-test-image.jpg"
  }
}