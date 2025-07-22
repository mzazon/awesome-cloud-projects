# Outputs for VMware workload migration and modernization infrastructure
# This file defines all output values from the Terraform configuration

# Project Information
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

# VMware Engine Outputs
output "vmware_private_cloud_name" {
  description = "Name of the VMware Engine private cloud"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.name
}

output "vmware_private_cloud_id" {
  description = "ID of the VMware Engine private cloud"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.id
}

output "vmware_private_cloud_state" {
  description = "State of the VMware Engine private cloud"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.state
}

output "vmware_private_cloud_uid" {
  description = "UID of the VMware Engine private cloud"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.uid
}

output "vmware_management_range" {
  description = "Management IP range for VMware Engine"
  value       = var.vmware_management_range
}

output "vmware_engine_network_name" {
  description = "Name of the VMware Engine network"
  value       = google_vmwareengine_network.vmware_engine_network.name
}

output "vmware_engine_network_id" {
  description = "ID of the VMware Engine network"
  value       = google_vmwareengine_network.vmware_engine_network.id
}

output "vmware_node_count" {
  description = "Number of nodes in the VMware Engine cluster"
  value       = var.vmware_node_count
}

output "vmware_node_type" {
  description = "Node type for VMware Engine cluster"
  value       = var.vmware_node_type
}

# vCenter and NSX Information
output "vcenter_web_url" {
  description = "vCenter Server web interface URL"
  value       = "https://${google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip}"
  sensitive   = false
}

output "vcenter_internal_ip" {
  description = "vCenter Server internal IP address"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip
}

output "vcenter_version" {
  description = "vCenter Server version"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].version
}

output "vcenter_fqdn" {
  description = "vCenter Server FQDN"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].fqdn
}

output "nsx_manager_web_url" {
  description = "NSX Manager web interface URL"
  value       = "https://${google_vmwareengine_private_cloud.vmware_private_cloud.nsx[0].internal_ip}"
  sensitive   = false
}

output "nsx_manager_internal_ip" {
  description = "NSX Manager internal IP address"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.nsx[0].internal_ip
}

output "nsx_manager_version" {
  description = "NSX Manager version"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.nsx[0].version
}

output "nsx_manager_fqdn" {
  description = "NSX Manager FQDN"
  value       = google_vmwareengine_private_cloud.vmware_private_cloud.nsx[0].fqdn
}

# HCX Configuration Information
output "hcx_setup_instructions" {
  description = "Instructions for setting up HCX connectivity"
  value = <<-EOT
    To configure HCX for workload migration:
    
    1. Access vCenter Server at: https://${google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip}
    2. Configure HCX Manager with the following settings:
       - Cloud HCX URL: https://${google_vmwareengine_private_cloud.vmware_private_cloud.hcx[0].internal_ip}
       - HCX Manager FQDN: ${google_vmwareengine_private_cloud.vmware_private_cloud.hcx[0].fqdn}
       - HCX Version: ${google_vmwareengine_private_cloud.vmware_private_cloud.hcx[0].version}
    3. Create service mesh between on-premises and cloud environments
    4. Configure network profiles and compute profiles
    5. Begin workload migration using HCX mobility groups
    
    Network Configuration:
    - Management Network: ${var.vmware_management_range}
    - VPC Network: ${google_compute_network.vmware_network.name}
    - Subnet: ${google_compute_subnetwork.vmware_mgmt_subnet.name}
  EOT
}

# Networking Outputs
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vmware_network.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vmware_network.id
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vmware_network.self_link
}

output "subnet_name" {
  description = "Name of the management subnet"
  value       = google_compute_subnetwork.vmware_mgmt_subnet.name
}

output "subnet_id" {
  description = "ID of the management subnet"
  value       = google_compute_subnetwork.vmware_mgmt_subnet.id
}

output "subnet_cidr" {
  description = "CIDR range of the management subnet"
  value       = google_compute_subnetwork.vmware_mgmt_subnet.ip_cidr_range
}

output "secondary_pod_range" {
  description = "Secondary IP range for GKE pods"
  value       = var.secondary_pod_range
}

output "secondary_service_range" {
  description = "Secondary IP range for GKE services"
  value       = var.secondary_service_range
}

output "vpn_gateway_name" {
  description = "Name of the VPN gateway"
  value       = google_compute_vpn_gateway.vmware_vpn_gateway.name
}

output "vpn_gateway_id" {
  description = "ID of the VPN gateway"
  value       = google_compute_vpn_gateway.vmware_vpn_gateway.id
}

# GKE Cluster Outputs
output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.name
}

output "gke_cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.id
}

output "gke_cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "CA certificate of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.location
}

output "gke_cluster_node_version" {
  description = "Node version of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.node_version
}

output "gke_cluster_master_version" {
  description = "Master version of the GKE cluster"
  value       = google_container_cluster.modernized_apps_cluster.master_version
}

output "gke_node_pool_name" {
  description = "Name of the GKE node pool"
  value       = google_container_node_pool.modernized_apps_nodes.name
}

output "gke_node_pool_version" {
  description = "Version of the GKE node pool"
  value       = google_container_node_pool.modernized_apps_nodes.version
}

output "gke_node_count" {
  description = "Current number of nodes in the GKE cluster"
  value       = google_container_node_pool.modernized_apps_nodes.node_count
}

output "gke_machine_type" {
  description = "Machine type for GKE nodes"
  value       = var.gke_machine_type
}

# kubectl Configuration Command
output "kubectl_config_command" {
  description = "Command to configure kubectl for the GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.modernized_apps_cluster.name} --region ${var.region} --project ${var.project_id}"
}

# Artifact Registry Outputs
output "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.modernized_apps.name
}

output "artifact_registry_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.modernized_apps.id
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.modernized_apps.location
}

output "artifact_registry_format" {
  description = "Format of the Artifact Registry repository"
  value       = google_artifact_registry_repository.modernized_apps.format
}

output "docker_registry_url" {
  description = "Docker registry URL for pushing images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.modernized_apps.repository_id}"
}

# Docker Configuration Command
output "docker_config_command" {
  description = "Command to configure Docker for Artifact Registry"
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
}

# Service Account Outputs
output "gke_nodes_service_account_email" {
  description = "Email of the GKE nodes service account"
  value       = google_service_account.gke_nodes.email
}

output "migrate_to_containers_service_account_email" {
  description = "Email of the Migrate to Containers service account"
  value       = google_service_account.migrate_to_containers.email
}

output "modernized_apps_workload_identity_email" {
  description = "Email of the modernized apps workload identity service account"
  value       = google_service_account.modernized_apps_workload_identity.email
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL of the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.hybrid_infrastructure[0].id}?project=${var.project_id}" : "Monitoring disabled"
}

output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

# Security Outputs
output "security_logs_bucket_name" {
  description = "Name of the security logs storage bucket"
  value       = google_storage_bucket.security_logs.name
}

output "security_logs_bucket_url" {
  description = "URL of the security logs storage bucket"
  value       = google_storage_bucket.security_logs.url
}

output "kms_key_ring_name" {
  description = "Name of the KMS key ring"
  value       = google_kms_key_ring.security_logs_keyring.name
}

output "kms_crypto_key_name" {
  description = "Name of the KMS crypto key"
  value       = google_kms_crypto_key.security_logs_key.name
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the billing budget"
  value       = var.enable_cost_management ? google_billing_budget.vmware_migration_budget[0].display_name : "Cost management disabled"
}

output "budget_amount" {
  description = "Budget amount in USD"
  value       = var.budget_amount
}

output "budget_threshold_percent" {
  description = "Budget threshold percentage"
  value       = var.budget_threshold_percent
}

# Migration Workspace Setup
output "migration_workspace_setup" {
  description = "Commands to set up the migration workspace"
  value = <<-EOT
    # Set up migration workspace
    mkdir -p ~/vmware-migration-workspace
    cd ~/vmware-migration-workspace
    
    # Configure environment variables
    export PROJECT_ID="${var.project_id}"
    export REGION="${var.region}"
    export ZONE="${var.zone}"
    export PRIVATE_CLOUD_NAME="${google_vmwareengine_private_cloud.vmware_private_cloud.name}"
    export GKE_CLUSTER_NAME="${google_container_cluster.modernized_apps_cluster.name}"
    export NETWORK_NAME="${google_compute_network.vmware_network.name}"
    export VCENTER_IP="${google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip}"
    export ARTIFACT_REGISTRY="${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.modernized_apps.repository_id}"
    
    # Configure kubectl
    ${self.kubectl_config_command}
    
    # Configure Docker
    ${self.docker_config_command}
    
    # Install Migrate to Containers CLI (run on your local machine)
    curl -O https://storage.googleapis.com/m2c-cli-release/m2c
    chmod +x m2c
    sudo mv m2c /usr/local/bin/
    
    echo "Migration workspace ready!"
  EOT
}

# Migrate to Containers Configuration
output "migrate_to_containers_config" {
  description = "Configuration for Migrate to Containers"
  value = <<-EOT
    # Create M2C configuration file
    cat > assessment-config.yaml << EOF
    apiVersion: v1
    kind: Config
    metadata:
      name: vmware-assessment
    spec:
      source:
        type: vmware
        connection:
          host: "${google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip}"
          username: "cloudowner@gve.local"
      target:
        registry: "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.modernized_apps.repository_id}"
        cluster: "${google_container_cluster.modernized_apps_cluster.name}"
    EOF
  EOT
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = <<-EOT
    # Verify VMware Engine private cloud
    gcloud vmware private-clouds describe ${google_vmwareengine_private_cloud.vmware_private_cloud.name} --location=${var.vmware_engine_region}
    
    # Verify GKE cluster
    gcloud container clusters describe ${google_container_cluster.modernized_apps_cluster.name} --region=${var.region}
    
    # Verify Artifact Registry
    gcloud artifacts repositories describe ${google_artifact_registry_repository.modernized_apps.repository_id} --location=${var.region}
    
    # Check monitoring dashboard
    echo "Monitoring dashboard: ${var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.hybrid_infrastructure[0].id}?project=${var.project_id}" : "Monitoring disabled"}"
    
    # Check security logs bucket
    gsutil ls gs://${google_storage_bucket.security_logs.name}/
  EOT
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vmware_private_cloud = {
      name         = google_vmwareengine_private_cloud.vmware_private_cloud.name
      state        = google_vmwareengine_private_cloud.vmware_private_cloud.state
      vcenter_ip   = google_vmwareengine_private_cloud.vmware_private_cloud.vcenter[0].internal_ip
      nsx_ip       = google_vmwareengine_private_cloud.vmware_private_cloud.nsx[0].internal_ip
      hcx_ip       = google_vmwareengine_private_cloud.vmware_private_cloud.hcx[0].internal_ip
      node_count   = var.vmware_node_count
      node_type    = var.vmware_node_type
    }
    gke_cluster = {
      name         = google_container_cluster.modernized_apps_cluster.name
      location     = google_container_cluster.modernized_apps_cluster.location
      endpoint     = google_container_cluster.modernized_apps_cluster.endpoint
      node_count   = google_container_node_pool.modernized_apps_nodes.node_count
      machine_type = var.gke_machine_type
    }
    networking = {
      vpc_network = google_compute_network.vmware_network.name
      subnet      = google_compute_subnetwork.vmware_mgmt_subnet.name
      subnet_cidr = google_compute_subnetwork.vmware_mgmt_subnet.ip_cidr_range
    }
    artifact_registry = {
      name     = google_artifact_registry_repository.modernized_apps.name
      location = google_artifact_registry_repository.modernized_apps.location
      format   = google_artifact_registry_repository.modernized_apps.format
    }
    monitoring = {
      enabled   = var.enable_monitoring
      dashboard = var.enable_monitoring ? google_monitoring_dashboard.hybrid_infrastructure[0].id : "disabled"
    }
    security = {
      logs_bucket = google_storage_bucket.security_logs.name
      kms_key     = google_kms_crypto_key.security_logs_key.name
    }
    cost_management = {
      enabled         = var.enable_cost_management
      budget_amount   = var.budget_amount
      budget_threshold = var.budget_threshold_percent
    }
  }
}