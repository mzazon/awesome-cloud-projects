# Output definitions for GCP Enterprise Kubernetes Fleet Management
# These outputs provide essential information for managing and monitoring the deployed infrastructure

# =============================================================================
# PROJECT INFORMATION
# =============================================================================

output "fleet_host_project_id" {
  description = "The project ID of the fleet host project for centralized management"
  value       = local.fleet_host_project_id
}

output "workload_project_prod_id" {
  description = "The project ID of the production workload project"
  value       = local.workload_project_prod_id
}

output "workload_project_staging_id" {
  description = "The project ID of the staging workload project"
  value       = local.workload_project_staging_id
}

output "project_numbers" {
  description = "Project numbers for all created projects"
  value = {
    fleet_host_project     = var.fleet_host_project_id == null ? google_project.fleet_host[0].number : null
    workload_project_prod  = var.workload_project_prod_id == null ? google_project.workload_prod[0].number : null
    workload_project_staging = var.workload_project_staging_id == null ? google_project.workload_staging[0].number : null
  }
}

# =============================================================================
# FLEET INFORMATION
# =============================================================================

output "fleet_name" {
  description = "The name of the GKE fleet for centralized management"
  value       = local.fleet_name
}

output "fleet_memberships" {
  description = "Fleet membership information for all registered clusters"
  value = {
    production = {
      membership_id = google_gke_hub_membership.prod_membership.membership_id
      cluster_name  = local.prod_cluster_name
      project       = local.workload_project_prod_id
      location      = var.region
    }
    staging = {
      membership_id = google_gke_hub_membership.staging_membership.membership_id
      cluster_name  = local.staging_cluster_name
      project       = local.workload_project_staging_id
      location      = var.region
    }
  }
}

# =============================================================================
# GKE CLUSTER INFORMATION
# =============================================================================

output "prod_cluster_info" {
  description = "Production GKE cluster information"
  value = {
    name              = google_container_cluster.prod_cluster.name
    location          = google_container_cluster.prod_cluster.location
    endpoint          = google_container_cluster.prod_cluster.endpoint
    cluster_ca_certificate = base64decode(google_container_cluster.prod_cluster.master_auth[0].cluster_ca_certificate)
    project           = local.workload_project_prod_id
    self_link         = google_container_cluster.prod_cluster.self_link
    services_ipv4_cidr = google_container_cluster.prod_cluster.services_ipv4_cidr
    cluster_ipv4_cidr = google_container_cluster.prod_cluster.cluster_ipv4_cidr
  }
  sensitive = true
}

output "staging_cluster_info" {
  description = "Staging GKE cluster information"
  value = {
    name              = google_container_cluster.staging_cluster.name
    location          = google_container_cluster.staging_cluster.location
    endpoint          = google_container_cluster.staging_cluster.endpoint
    cluster_ca_certificate = base64decode(google_container_cluster.staging_cluster.master_auth[0].cluster_ca_certificate)
    project           = local.workload_project_staging_id
    self_link         = google_container_cluster.staging_cluster.self_link
    services_ipv4_cidr = google_container_cluster.staging_cluster.services_ipv4_cidr
    cluster_ipv4_cidr = google_container_cluster.staging_cluster.cluster_ipv4_cidr
  }
  sensitive = true
}

# Kubectl configuration commands for cluster access
output "kubectl_commands" {
  description = "Commands to configure kubectl for cluster access"
  value = {
    production = "gcloud container clusters get-credentials ${local.prod_cluster_name} --region ${var.region} --project ${local.workload_project_prod_id}"
    staging    = "gcloud container clusters get-credentials ${local.staging_cluster_name} --region ${var.region} --project ${local.workload_project_staging_id}"
  }
}

# =============================================================================
# NETWORK INFORMATION
# =============================================================================

output "network_info" {
  description = "Network configuration information for the clusters"
  value = var.network_config.create_vpc_network ? {
    production = {
      network_name    = google_compute_network.prod_network[0].name
      network_id      = google_compute_network.prod_network[0].id
      subnet_name     = google_compute_subnetwork.prod_subnet[0].name
      subnet_cidr     = google_compute_subnetwork.prod_subnet[0].ip_cidr_range
      pods_cidr       = var.network_config.pods_cidr
      services_cidr   = var.network_config.services_cidr
    }
    staging = {
      network_name    = google_compute_network.staging_network[0].name
      network_id      = google_compute_network.staging_network[0].id
      subnet_name     = google_compute_subnetwork.staging_subnet[0].name
      subnet_cidr     = google_compute_subnetwork.staging_subnet[0].ip_cidr_range
      pods_cidr       = "10.11.0.0/16"
      services_cidr   = "10.12.0.0/16"
    }
  } : null
}

# =============================================================================
# SERVICE ACCOUNT INFORMATION
# =============================================================================

output "service_accounts" {
  description = "Service account information for fleet operations"
  value = {
    fleet_manager = {
      email       = google_service_account.fleet_manager.email
      unique_id   = google_service_account.fleet_manager.unique_id
      member      = google_service_account.fleet_manager.member
    }
    config_connector_prod = var.enable_config_connector ? {
      email     = google_service_account.config_connector_prod[0].email
      unique_id = google_service_account.config_connector_prod[0].unique_id
      member    = google_service_account.config_connector_prod[0].member
    } : null
    config_connector_staging = var.enable_config_connector ? {
      email     = google_service_account.config_connector_staging[0].email
      unique_id = google_service_account.config_connector_staging[0].unique_id
      member    = google_service_account.config_connector_staging[0].member
    } : null
  }
}

# =============================================================================
# BACKUP INFORMATION
# =============================================================================

output "backup_plans" {
  description = "Backup plan information for GKE clusters"
  value = var.enable_backup ? {
    production = {
      name        = google_gke_backup_backup_plan.prod_backup_plan[0].name
      id          = google_gke_backup_backup_plan.prod_backup_plan[0].id
      schedule    = var.backup_plan_config.prod_schedule
      retention   = "${var.backup_plan_config.prod_retention_days} days"
      description = google_gke_backup_backup_plan.prod_backup_plan[0].description
    }
    staging = {
      name        = google_gke_backup_backup_plan.staging_backup_plan[0].name
      id          = google_gke_backup_backup_plan.staging_backup_plan[0].id
      schedule    = var.backup_plan_config.staging_schedule
      retention   = "${var.backup_plan_config.staging_retention_days} days"
      description = google_gke_backup_backup_plan.staging_backup_plan[0].description
    }
  } : null
}

# Commands to trigger manual backups
output "backup_commands" {
  description = "Commands to create manual backups for testing"
  value = var.enable_backup ? {
    production = "gcloud backup-dr backups create test-backup-prod-$(date +%s) --location=${var.region} --backup-plan=${google_gke_backup_backup_plan.prod_backup_plan[0].name} --project=${local.fleet_host_project_id}"
    staging    = "gcloud backup-dr backups create test-backup-staging-$(date +%s) --location=${var.region} --backup-plan=${google_gke_backup_backup_plan.staging_backup_plan[0].name} --project=${local.fleet_host_project_id}"
  } : null
}

# =============================================================================
# CONFIG MANAGEMENT INFORMATION
# =============================================================================

output "config_management_status" {
  description = "Configuration management feature status"
  value = {
    feature_enabled = google_gke_hub_feature.config_management.name
    fleet_project   = local.fleet_host_project_id
    memberships = {
      production = google_gke_hub_feature_membership.prod_config_management.membership
      staging    = google_gke_hub_feature_membership.staging_config_management.membership
    }
  }
}

# Commands to check config management status
output "config_management_commands" {
  description = "Commands to monitor and manage config management"
  value = {
    status_check    = "gcloud container fleet config-management status --project=${local.fleet_host_project_id}"
    feature_status  = "gcloud container fleet features list --project=${local.fleet_host_project_id}"
    membership_list = "gcloud container fleet memberships list --project=${local.fleet_host_project_id}"
  }
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

output "monitoring_info" {
  description = "Monitoring and observability configuration"
  value = var.enable_monitoring ? {
    logging_service    = "logging.googleapis.com/kubernetes"
    monitoring_service = "monitoring.googleapis.com/kubernetes"
    dashboards = {
      fleet_overview = "https://console.cloud.google.com/kubernetes/workload/overview?project=${local.fleet_host_project_id}"
      prod_cluster   = "https://console.cloud.google.com/kubernetes/workload/overview?project=${local.workload_project_prod_id}"
      staging_cluster = "https://console.cloud.google.com/kubernetes/workload/overview?project=${local.workload_project_staging_id}"
    }
  } : null
}

# =============================================================================
# DEPLOYMENT VERIFICATION
# =============================================================================

output "deployment_verification" {
  description = "Commands and information for verifying the deployment"
  value = {
    fleet_status_commands = {
      membership_status = "gcloud container fleet memberships list --project=${local.fleet_host_project_id}"
      cluster_health    = "gcloud container clusters list --project=${local.workload_project_prod_id} && gcloud container clusters list --project=${local.workload_project_staging_id}"
      backup_plans      = var.enable_backup ? "gcloud backup-dr backup-plans list --location=${var.region} --project=${local.fleet_host_project_id}" : "Backup is disabled"
    }
    access_commands = {
      prod_context    = "kubectl config set-context prod-context --cluster=gke_${local.workload_project_prod_id}_${var.region}_${local.prod_cluster_name} --user=gke_${local.workload_project_prod_id}_${var.region}_${local.prod_cluster_name}"
      staging_context = "kubectl config set-context staging-context --cluster=gke_${local.workload_project_staging_id}_${var.region}_${local.staging_cluster_name} --user=gke_${local.workload_project_staging_id}_${var.region}_${local.staging_cluster_name}"
    }
  }
}

# =============================================================================
# COST INFORMATION
# =============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    cluster_costs = {
      production = "~$150-300/month (2-5 e2-standard-4 nodes)"
      staging    = "~$75-150/month (1-3 e2-standard-2 nodes)"
    }
    additional_costs = {
      backup_storage = "~$0.10/GB/month for backup storage"
      network_egress = "Variable based on traffic patterns"
      monitoring     = "Included in cluster cost for standard metrics"
    }
    cost_optimization = [
      "Use preemptible nodes for non-production workloads",
      "Enable cluster autoscaling to optimize resource usage",
      "Configure appropriate backup retention policies",
      "Monitor resource utilization with GKE usage metering"
    ]
  }
}

# =============================================================================
# NEXT STEPS
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate_actions = [
      "Verify cluster connectivity using kubectl_commands",
      "Check fleet membership status",
      "Test backup plan execution if enabled",
      "Deploy sample applications for testing"
    ]
    configuration_tasks = [
      "Set up GitOps repository for Config Sync",
      "Configure Binary Authorization policies",
      "Implement Pod Security Standards",
      "Set up monitoring dashboards and alerts"
    ]
    security_enhancements = [
      "Configure Workload Identity for applications",
      "Implement network policies for microsegmentation",
      "Set up VPN or Private Google Access",
      "Enable audit logging and review security events"
    ]
  }
}

# Random suffix for reference
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}