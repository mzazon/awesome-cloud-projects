# Output Values
# Remote Developer Onboarding with Cloud Workstations and Firebase Studio

# Project and Basic Information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
}

# Workstation Cluster Information
output "workstation_cluster_id" {
  description = "The ID of the workstation cluster"
  value       = google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id
}

output "workstation_cluster_name" {
  description = "The full name of the workstation cluster"
  value       = google_workstations_workstation_cluster.developer_cluster.name
}

output "workstation_cluster_display_name" {
  description = "The display name of the workstation cluster"
  value       = google_workstations_workstation_cluster.developer_cluster.display_name
}

output "workstation_cluster_state" {
  description = "The current state of the workstation cluster"
  value       = google_workstations_workstation_cluster.developer_cluster.state
}

output "workstation_cluster_create_time" {
  description = "The creation time of the workstation cluster"
  value       = google_workstations_workstation_cluster.developer_cluster.create_time
}

# Workstation Configuration Information
output "workstation_config_id" {
  description = "The ID of the workstation configuration"
  value       = google_workstations_workstation_config.fullstack_dev_config.workstation_config_id
}

output "workstation_config_name" {
  description = "The full name of the workstation configuration"
  value       = google_workstations_workstation_config.fullstack_dev_config.name
}

output "workstation_config_display_name" {
  description = "The display name of the workstation configuration"
  value       = google_workstations_workstation_config.fullstack_dev_config.display_name
}

output "workstation_machine_type" {
  description = "The machine type used for workstations"
  value       = var.machine_type
}

output "workstation_persistent_disk_size" {
  description = "The persistent disk size for workstations (in GB)"
  value       = var.persistent_disk_size_gb
}

output "workstation_idle_timeout" {
  description = "The idle timeout for workstations (in seconds)"
  value       = var.idle_timeout_seconds
}

output "workstation_container_image" {
  description = "The container image used for workstations"
  value       = var.workstation_container_image
}

# Source Repository Information
output "source_repository_name" {
  description = "The name of the Cloud Source Repository for team templates"
  value       = google_sourcerepo_repository.team_templates.name
}

output "source_repository_url" {
  description = "The URL of the Cloud Source Repository"
  value       = google_sourcerepo_repository.team_templates.url
}

output "source_repository_clone_url" {
  description = "The clone URL for the source repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.team_templates.name}"
}

# Service Account Information
output "workstation_service_account_email" {
  description = "The email address of the workstation service account"
  value       = google_service_account.workstation_service_account.email
}

output "workstation_service_account_unique_id" {
  description = "The unique ID of the workstation service account"
  value       = google_service_account.workstation_service_account.unique_id
}

# IAM and Security Information
output "custom_iam_role_name" {
  description = "The name of the custom IAM role for workstation developers"
  value       = google_project_iam_custom_role.workstation_developer.name
}

output "custom_iam_role_id" {
  description = "The ID of the custom IAM role for workstation developers"
  value       = google_project_iam_custom_role.workstation_developer.role_id
}

output "developer_users_granted_access" {
  description = "List of developer users granted workstation access"
  value       = var.developer_users
}

output "admin_users_granted_access" {
  description = "List of admin users granted administrative access"
  value       = var.admin_users
}

# Firebase Integration Information
output "firebase_project_id" {
  description = "The Firebase project ID"
  value       = google_firebase_project.default.project
}

output "firebase_location" {
  description = "The Firebase project location"
  value       = google_firebase_project_location.default.location_id
}

output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = google_firestore_database.default.name
}

output "firestore_database_type" {
  description = "The type of the Firestore database"
  value       = google_firestore_database.default.type
}

# Network Configuration
output "network_name" {
  description = "The name of the VPC network used by workstations"
  value       = var.network_name
}

output "subnet_name" {
  description = "The name of the subnet used by workstations"
  value       = var.subnet_name
}

output "private_endpoint_enabled" {
  description = "Whether private endpoint is enabled for the workstation cluster"
  value       = var.enable_private_endpoint
}

# Monitoring and Alerting Information
output "monitoring_dashboard_id" {
  description = "The ID of the monitoring dashboard (if created)"
  value       = var.enable_monitoring_dashboard ? google_monitoring_dashboard.workstation_dashboard[0].id : null
}

output "notification_channel_id" {
  description = "The ID of the email notification channel (if created)"
  value       = length(var.admin_users) > 0 ? google_monitoring_notification_channel.email_alert[0].name : null
}

output "billing_budget_name" {
  description = "The name of the billing budget (if created)"
  value       = length(var.admin_users) > 0 ? google_billing_budget.developer_workstations_budget[0].name : null
}

output "log_metric_name" {
  description = "The name of the workstation creation log metric"
  value       = google_logging_metric.workstation_creation_metric.name
}

# Cost Management Information
output "budget_amount" {
  description = "The monthly budget amount configured (in USD)"
  value       = var.budget_amount
}

output "budget_alert_thresholds" {
  description = "The budget alert thresholds configured"
  value       = var.budget_alert_thresholds
}

# Resource Labels and Metadata
output "environment" {
  description = "The environment label applied to resources"
  value       = var.environment
}

output "team" {
  description = "The team label applied to resources"
  value       = var.team
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# API Services Information
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = [
    "workstations.googleapis.com",
    "sourcerepo.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "firestore.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbilling.googleapis.com"
  ]
}

# Deployment Instructions
output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = <<-EOT
    
    🚀 Cloud Workstations Developer Onboarding Infrastructure Deployed Successfully!
    
    📋 Next Steps:
    
    1. Access Cloud Workstations:
       - Go to: https://console.cloud.google.com/workstations
       - Select project: ${var.project_id}
       - Create workstation instances for your developers
    
    2. Clone Team Templates Repository:
       - Repository URL: ${google_sourcerepo_repository.team_templates.url}
       - Clone command: gcloud source repos clone ${google_sourcerepo_repository.team_templates.name}
    
    3. Configure Firebase Studio:
       - Access Firebase Console: https://console.firebase.google.com/project/${var.project_id}
       - Set up Firebase Studio projects and templates
    
    4. Create Developer Workstations:
       - Use the configuration: ${google_workstations_workstation_config.fullstack_dev_config.workstation_config_id}
       - Assign to users in: ${var.developer_users != [] ? join(", ", var.developer_users) : "Add developer emails to var.developer_users"}
    
    5. Monitor Usage:
       - View dashboard: https://console.cloud.google.com/monitoring/dashboards
       - Check budget alerts: https://console.cloud.google.com/billing/budgets
    
    📊 Resource Summary:
    - Workstation Cluster: ${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id}
    - Configuration: ${google_workstations_workstation_config.fullstack_dev_config.workstation_config_id}
    - Machine Type: ${var.machine_type}
    - Disk Size: ${var.persistent_disk_size_gb}GB
    - Budget: $${var.budget_amount}/month
    
    💡 Tips:
    - Workstations auto-shutdown after ${var.idle_timeout_seconds / 60} minutes of inactivity
    - Use 'gcloud workstations' CLI for automation
    - Check monitoring dashboard for usage insights
    
    EOT
}

# Workstation Creation Commands
output "workstation_creation_commands" {
  description = "Sample commands to create workstations for users"
  value = var.developer_users != [] ? {
    for user in var.developer_users :
    replace(user, "@", "_at_") => {
      gcloud_command = "gcloud beta workstations create ${replace(user, "@", "-")}-workstation --cluster=${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id} --config=${google_workstations_workstation_config.fullstack_dev_config.workstation_config_id} --region=${var.region}"
      
      iam_command = "gcloud beta workstations add-iam-policy-binding ${replace(user, "@", "-")}-workstation --cluster=${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id} --config=${google_workstations_workstation_config.fullstack_dev_config.workstation_config_id} --region=${var.region} --member='user:${user}' --role='roles/workstations.user'"
    }
  } : {}
}

# Resource URLs for Quick Access
output "quick_access_urls" {
  description = "Quick access URLs for key resources"
  value = {
    workstations_console = "https://console.cloud.google.com/workstations?project=${var.project_id}"
    firebase_console     = "https://console.firebase.google.com/project/${var.project_id}"
    source_repo_console  = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    monitoring_console   = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    billing_console      = "https://console.cloud.google.com/billing/budgets?project=${var.project_id}"
    iam_console         = "https://console.cloud.google.com/iam-admin/iam?project=${var.project_id}"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Troubleshooting information and common commands"
  value = {
    check_cluster_status = "gcloud beta workstations clusters describe ${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id} --region=${var.region}"
    
    list_configurations = "gcloud beta workstations configs list --cluster=${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id} --region=${var.region}"
    
    check_api_status = "gcloud services list --enabled --filter='name:workstations OR name:firebase OR name:sourcerepo'"
    
    view_logs = "gcloud logging read 'resource.type=\"workstations.googleapis.com/Workstation\"' --limit=50"
    
    check_permissions = "gcloud projects get-iam-policy ${var.project_id} --flatten='bindings[].members' --format='table(bindings.role)' --filter='bindings.members:user:YOUR_EMAIL'"
  }
}

# Security and Compliance Information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    private_endpoints    = var.enable_private_endpoint
    audit_logging       = var.enable_audit_logging
    custom_iam_roles    = true
    service_account     = google_service_account.workstation_service_account.email
    encrypted_storage   = true
    network_isolation   = var.enable_private_endpoint
    monitoring_alerts   = length(var.admin_users) > 0
    budget_controls     = length(var.admin_users) > 0
  }
}