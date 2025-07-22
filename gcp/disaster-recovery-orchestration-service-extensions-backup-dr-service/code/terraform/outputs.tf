# outputs.tf
# Output values for the disaster recovery orchestration infrastructure

# ================================
# LOAD BALANCER OUTPUTS
# ================================

output "load_balancer_ip" {
  description = "External IP address of the global load balancer"
  value       = google_compute_global_forwarding_rule.dr_orchestration.ip_address
}

output "load_balancer_url" {
  description = "Complete URL to access the load-balanced application"
  value       = "http://${google_compute_global_forwarding_rule.dr_orchestration.ip_address}"
}

output "url_map_name" {
  description = "Name of the URL map for traffic routing"
  value       = google_compute_url_map.dr_orchestration.name
}

# ================================
# INSTANCE GROUP OUTPUTS
# ================================

output "primary_instance_group" {
  description = "Details of the primary application instance group"
  value = {
    name               = google_compute_instance_group_manager.primary_app.name
    zone               = google_compute_instance_group_manager.primary_app.zone
    target_size        = google_compute_instance_group_manager.primary_app.target_size
    instance_group_url = google_compute_instance_group_manager.primary_app.instance_group
  }
}

output "dr_instance_group" {
  description = "Details of the disaster recovery instance group"
  value = {
    name               = google_compute_instance_group_manager.dr_app.name
    zone               = google_compute_instance_group_manager.dr_app.zone
    target_size        = google_compute_instance_group_manager.dr_app.target_size
    instance_group_url = google_compute_instance_group_manager.dr_app.instance_group
  }
}

# ================================
# BACKUP AND DR SERVICE OUTPUTS
# ================================

output "backup_vault" {
  description = "Details of the backup vault for disaster recovery"
  value = {
    name     = google_backup_dr_backup_vault.primary.name
    location = google_backup_dr_backup_vault.primary.location
    state    = google_backup_dr_backup_vault.primary.state
  }
}

output "backup_plan" {
  description = "Details of the backup plan configuration"
  value = {
    name          = google_backup_dr_backup_plan.primary.name
    location      = google_backup_dr_backup_plan.primary.location
    resource_type = google_backup_dr_backup_plan.primary.resource_type
    backup_vault  = google_backup_dr_backup_plan.primary.backup_vault
  }
}

# ================================
# CLOUD FUNCTION OUTPUTS
# ================================

output "dr_orchestrator_function" {
  description = "Details of the disaster recovery orchestrator Cloud Function"
  value = {
    name         = google_cloudfunctions_function.dr_orchestrator.name
    trigger_url  = google_cloudfunctions_function.dr_orchestrator.https_trigger_url
    region       = google_cloudfunctions_function.dr_orchestrator.region
    runtime      = google_cloudfunctions_function.dr_orchestrator.runtime
    memory       = google_cloudfunctions_function.dr_orchestrator.available_memory_mb
  }
}

output "dr_function_trigger_url" {
  description = "HTTPS trigger URL for the disaster recovery orchestrator function"
  value       = google_cloudfunctions_function.dr_orchestrator.https_trigger_url
  sensitive   = false
}

output "dr_service_account_email" {
  description = "Email address of the disaster recovery service account"
  value       = google_service_account.dr_orchestrator.email
}

# ================================
# HEALTH CHECK OUTPUTS
# ================================

output "primary_health_check" {
  description = "Details of the primary application health check"
  value = {
    name                = google_compute_health_check.primary_app.name
    check_interval_sec  = google_compute_health_check.primary_app.check_interval_sec
    timeout_sec         = google_compute_health_check.primary_app.timeout_sec
    healthy_threshold   = google_compute_health_check.primary_app.healthy_threshold
    unhealthy_threshold = google_compute_health_check.primary_app.unhealthy_threshold
  }
}

output "dr_health_check" {
  description = "Details of the disaster recovery application health check"
  value = {
    name                = google_compute_health_check.dr_app.name
    check_interval_sec  = google_compute_health_check.dr_app.check_interval_sec
    timeout_sec         = google_compute_health_check.dr_app.timeout_sec
    healthy_threshold   = google_compute_health_check.dr_app.healthy_threshold
    unhealthy_threshold = google_compute_health_check.dr_app.unhealthy_threshold
  }
}

# ================================
# BACKEND SERVICE OUTPUTS
# ================================

output "primary_backend_service" {
  description = "Details of the primary backend service"
  value = {
    name         = google_compute_backend_service.primary.name
    protocol     = google_compute_backend_service.primary.protocol
    port_name    = google_compute_backend_service.primary.port_name
    timeout_sec  = google_compute_backend_service.primary.timeout_sec
    self_link    = google_compute_backend_service.primary.self_link
  }
}

output "dr_backend_service" {
  description = "Details of the disaster recovery backend service"
  value = {
    name         = google_compute_backend_service.dr.name
    protocol     = google_compute_backend_service.dr.protocol
    port_name    = google_compute_backend_service.dr.port_name
    timeout_sec  = google_compute_backend_service.dr.timeout_sec
    self_link    = google_compute_backend_service.dr.self_link
  }
}

# ================================
# MONITORING OUTPUTS
# ================================

output "monitoring_dashboard_url" {
  description = "URL to access the disaster recovery monitoring dashboard"
  value = var.enable_monitoring && length(google_monitoring_dashboard.dr_orchestration) > 0 ? (
    "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.dr_orchestration[0].id}?project=${var.project_id}"
  ) : "Monitoring disabled or dashboard not created"
}

output "log_metrics" {
  description = "Details of the log-based metrics for monitoring"
  value = var.enable_monitoring ? {
    failure_detection = length(google_logging_metric.dr_failure_detection) > 0 ? {
      name   = google_logging_metric.dr_failure_detection[0].name
      filter = google_logging_metric.dr_failure_detection[0].filter
    } : null
    orchestration_success = length(google_logging_metric.dr_orchestration_success) > 0 ? {
      name   = google_logging_metric.dr_orchestration_success[0].name
      filter = google_logging_metric.dr_orchestration_success[0].filter
    } : null
  } : "Monitoring disabled"
}

output "alert_policy" {
  description = "Details of the disaster recovery alert policy"
  value = var.enable_monitoring && length(google_monitoring_alert_policy.dr_events) > 0 ? {
    name         = google_monitoring_alert_policy.dr_events[0].name
    display_name = google_monitoring_alert_policy.dr_events[0].display_name
    enabled      = google_monitoring_alert_policy.dr_events[0].enabled
  } : "Monitoring disabled or alert policy not created"
}

# ================================
# NETWORK OUTPUTS
# ================================

output "firewall_rule" {
  description = "Details of the HTTP firewall rule"
  value = {
    name          = google_compute_firewall.allow_http.name
    direction     = google_compute_firewall.allow_http.direction
    source_ranges = google_compute_firewall.allow_http.source_ranges
    target_tags   = google_compute_firewall.allow_http.target_tags
  }
}

# ================================
# PROJECT AND CONFIGURATION OUTPUTS
# ================================

output "project_id" {
  description = "GCP project ID where resources were created"
  value       = var.project_id
}

output "primary_region" {
  description = "Primary region for the application infrastructure"
  value       = var.primary_region
}

output "dr_region" {
  description = "Disaster recovery region for failover infrastructure"
  value       = var.dr_region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# ================================
# VALIDATION COMMANDS
# ================================

output "validation_commands" {
  description = "Commands to validate the disaster recovery infrastructure"
  value = {
    test_primary_app = "curl -H 'Host: example.com' http://${google_compute_global_forwarding_rule.dr_orchestration.ip_address}"
    
    check_instance_groups = "gcloud compute instance-groups managed describe ${google_compute_instance_group_manager.primary_app.name} --zone=${var.primary_zone}"
    
    check_backup_vault = "gcloud backup-dr backup-vaults describe ${google_backup_dr_backup_vault.primary.backup_vault_id} --location=${var.primary_region}"
    
    check_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.dr_orchestrator.name} --limit=10"
    
    trigger_dr_test = "curl -X POST -H 'Content-Type: application/json' -d '{\"failure_type\":\"test\",\"severity\":\"high\"}' ${google_cloudfunctions_function.dr_orchestrator.https_trigger_url}"
  }
}

# ================================
# CLEANUP COMMANDS
# ================================

output "cleanup_commands" {
  description = "Commands to clean up the disaster recovery infrastructure"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    
    manual_cleanup = [
      "gcloud compute forwarding-rules delete ${google_compute_global_forwarding_rule.dr_orchestration.name} --global --quiet",
      "gcloud compute backend-services delete ${google_compute_backend_service.primary.name} --global --quiet",
      "gcloud compute instance-groups managed delete ${google_compute_instance_group_manager.primary_app.name} --zone=${var.primary_zone} --quiet",
      "gcloud functions delete ${google_cloudfunctions_function.dr_orchestrator.name} --region=${var.primary_region} --quiet"
    ]
  }
}

# ================================
# COST ESTIMATION
# ================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure (USD)"
  value = {
    compute_instances = "Primary: $${var.primary_instance_count * 5.50} (e2-micro), DR: $${var.dr_initial_instance_count * 5.50}"
    load_balancer     = "$18.00 (Global HTTP(S) Load Balancer)"
    cloud_function    = "$0.40 (2M invocations @ $0.0000004/invocation + $0.0000025/GB-second)"
    backup_storage    = "$20.00 (100GB backup storage)"
    monitoring        = "$0.50 (Custom metrics and dashboards)"
    total_estimate    = "$44.40 + compute costs"
    note             = "Costs may vary based on actual usage, data transfer, and additional features"
  }
}