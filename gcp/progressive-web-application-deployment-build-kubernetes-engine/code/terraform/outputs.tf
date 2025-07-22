# Project Information
output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

# Network Outputs
output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc_network.name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.vpc_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_self_link" {
  description = "Self link of the subnet"
  value       = google_compute_subnetwork.subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

# GKE Cluster Outputs - Blue Environment
output "blue_cluster_name" {
  description = "Name of the blue GKE cluster"
  value       = google_container_cluster.blue_cluster.name
}

output "blue_cluster_endpoint" {
  description = "Endpoint of the blue GKE cluster"
  value       = google_container_cluster.blue_cluster.endpoint
  sensitive   = true
}

output "blue_cluster_ca_certificate" {
  description = "CA certificate of the blue GKE cluster"
  value       = google_container_cluster.blue_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "blue_cluster_location" {
  description = "Location of the blue GKE cluster"
  value       = google_container_cluster.blue_cluster.location
}

output "blue_cluster_node_pool_name" {
  description = "Name of the blue cluster node pool"
  value       = google_container_node_pool.blue_nodes.name
}

# GKE Cluster Outputs - Green Environment
output "green_cluster_name" {
  description = "Name of the green GKE cluster"
  value       = google_container_cluster.green_cluster.name
}

output "green_cluster_endpoint" {
  description = "Endpoint of the green GKE cluster"
  value       = google_container_cluster.green_cluster.endpoint
  sensitive   = true
}

output "green_cluster_ca_certificate" {
  description = "CA certificate of the green GKE cluster"
  value       = google_container_cluster.green_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "green_cluster_location" {
  description = "Location of the green GKE cluster"
  value       = google_container_cluster.green_cluster.location
}

output "green_cluster_node_pool_name" {
  description = "Name of the green cluster node pool"
  value       = google_container_node_pool.green_nodes.name
}

# Service Account Outputs
output "gke_service_account_email" {
  description = "Email of the GKE service account"
  value       = google_service_account.gke_service_account.email
}

output "cloud_build_service_account_email" {
  description = "Email of the Cloud Build service account"
  value       = google_service_account.cloud_build_sa.email
}

# Cloud Storage Outputs
output "pwa_assets_bucket_name" {
  description = "Name of the Cloud Storage bucket for PWA assets"
  value       = google_storage_bucket.pwa_assets.name
}

output "pwa_assets_bucket_url" {
  description = "URL of the Cloud Storage bucket for PWA assets"
  value       = google_storage_bucket.pwa_assets.url
}

output "pwa_assets_bucket_self_link" {
  description = "Self link of the Cloud Storage bucket for PWA assets"
  value       = google_storage_bucket.pwa_assets.self_link
}

# Cloud Build Outputs
output "source_repository_name" {
  description = "Name of the Cloud Source Repository"
  value       = google_sourcerepo_repository.pwa_repo.name
}

output "source_repository_url" {
  description = "URL of the Cloud Source Repository"
  value       = google_sourcerepo_repository.pwa_repo.url
}

output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.pwa_build_trigger.name
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.pwa_build_trigger.trigger_id
}

# Load Balancer Outputs
output "static_ip_address" {
  description = "Static IP address for the load balancer"
  value       = google_compute_global_address.static_ip.address
}

output "static_ip_name" {
  description = "Name of the static IP address"
  value       = google_compute_global_address.static_ip.name
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = google_compute_managed_ssl_certificate.ssl_cert.name
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = google_compute_managed_ssl_certificate.ssl_cert.managed[0].domains
}

# Application Configuration Outputs
output "app_name" {
  description = "Name of the PWA application"
  value       = var.app_name
}

output "app_version" {
  description = "Version of the PWA application"
  value       = var.app_version
}

# Kubectl Connection Commands
output "kubectl_connect_blue_cluster" {
  description = "Command to connect kubectl to the blue cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.blue_cluster.name} --region ${google_container_cluster.blue_cluster.location} --project ${var.project_id}"
}

output "kubectl_connect_green_cluster" {
  description = "Command to connect kubectl to the green cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.green_cluster.name} --region ${google_container_cluster.green_cluster.location} --project ${var.project_id}"
}

# Monitoring and Logging Outputs
output "monitoring_dashboard_url" {
  description = "URL of the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.pwa_dashboard.id}?project=${var.project_id}"
}

output "log_sink_name" {
  description = "Name of the log sink"
  value       = google_logging_project_sink.pwa_log_sink.name
}

output "notification_channel_name" {
  description = "Name of the notification channel"
  value       = google_monitoring_notification_channel.email_channel.name
}

output "alert_policy_name" {
  description = "Name of the alert policy"
  value       = google_monitoring_alert_policy.cluster_health_alert.name
}

# Container Registry Information
output "container_registry_url" {
  description = "URL of the container registry"
  value       = "gcr.io/${var.project_id}"
}

output "container_image_url" {
  description = "URL pattern for container images"
  value       = "gcr.io/${var.project_id}/${var.app_name}"
}

# Deployment Information
output "deployment_instructions" {
  description = "Instructions for deploying the PWA application"
  value = <<-EOT
    1. Clone the source repository:
       git clone ${google_sourcerepo_repository.pwa_repo.url}
    
    2. Connect to the blue cluster:
       ${output.kubectl_connect_blue_cluster.value}
    
    3. Connect to the green cluster:
       ${output.kubectl_connect_green_cluster.value}
    
    4. View the monitoring dashboard:
       ${output.monitoring_dashboard_url.value}
    
    5. Access the application at:
       http://${google_compute_global_address.static_ip.address}
    
    6. Container images will be available at:
       ${output.container_image_url.value}
  EOT
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    gke_clusters = {
      blue_cluster  = google_container_cluster.blue_cluster.name
      green_cluster = google_container_cluster.green_cluster.name
    }
    networking = {
      vpc_network    = google_compute_network.vpc_network.name
      subnet         = google_compute_subnetwork.subnet.name
      static_ip      = google_compute_global_address.static_ip.address
      ssl_certificate = google_compute_managed_ssl_certificate.ssl_cert.name
    }
    storage = {
      bucket_name = google_storage_bucket.pwa_assets.name
      bucket_url  = google_storage_bucket.pwa_assets.url
    }
    ci_cd = {
      repository_name = google_sourcerepo_repository.pwa_repo.name
      build_trigger   = google_cloudbuild_trigger.pwa_build_trigger.name
    }
    monitoring = {
      dashboard        = google_monitoring_dashboard.pwa_dashboard.id
      alert_policy     = google_monitoring_alert_policy.cluster_health_alert.name
      notification_channel = google_monitoring_notification_channel.email_channel.name
      log_sink         = google_logging_project_sink.pwa_log_sink.name
    }
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the infrastructure"
  value = <<-EOT
    Estimated Monthly Costs (USD):
    
    GKE Clusters (2 clusters):
    - Blue Cluster: ~$73/month (2 e2-medium nodes)
    - Green Cluster: ~$73/month (2 e2-medium nodes)
    
    Networking:
    - VPC Network: Free
    - Cloud NAT: ~$45/month
    - Global Load Balancer: ~$18/month
    - Static IP: ~$3/month
    
    Storage:
    - Cloud Storage: ~$1-5/month (depends on usage)
    
    CI/CD:
    - Cloud Build: ~$5-20/month (depends on build frequency)
    - Cloud Source Repository: Free
    
    Monitoring & Logging:
    - Cloud Monitoring: ~$1-10/month (depends on metrics)
    - Cloud Logging: ~$1-5/month (depends on log volume)
    
    Total Estimated Cost: ~$220-255/month
    
    Note: Costs may vary based on actual usage, region, and configuration.
    Consider using GKE Autopilot for cost optimization.
  EOT
}

# Security Information
output "security_recommendations" {
  description = "Security recommendations for the deployment"
  value = <<-EOT
    Security Recommendations:
    
    1. Update master authorized networks to restrict access
    2. Configure proper RBAC policies for Kubernetes
    3. Enable Binary Authorization for container image security
    4. Regular security scanning of container images
    5. Use Workload Identity for pod-level security
    6. Enable VPC Flow Logs for network monitoring
    7. Configure proper firewall rules
    8. Regular security audits and compliance checks
    9. Use private Google Access for secure API access
    10. Enable audit logging for GKE clusters
  EOT
}