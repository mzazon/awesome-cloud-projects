# Output Values for Performance Testing Pipeline Infrastructure
# This file defines outputs that provide important information about the deployed resources

# Load Balancer Information
output "load_balancer_ip" {
  description = "External IP address of the HTTP load balancer"
  value       = google_compute_global_forwarding_rule.app_forwarding_rule.ip_address
}

output "load_balancer_url" {
  description = "URL to access the load-balanced application"
  value       = "http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}"
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.app_backend.name
}

output "health_check_url" {
  description = "URL for the health check endpoint"
  value       = "http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}/health"
}

# Instance Group Information
output "instance_group_name" {
  description = "Name of the managed instance group"
  value       = google_compute_region_instance_group_manager.app_group.name
}

output "instance_group_url" {
  description = "Self-link URL of the managed instance group"
  value       = google_compute_region_instance_group_manager.app_group.self_link
}

output "autoscaler_name" {
  description = "Name of the autoscaler"
  value       = google_compute_region_autoscaler.app_autoscaler.name
}

output "instance_template_name" {
  description = "Name of the instance template"
  value       = google_compute_instance_template.app_template.name
}

# Cloud Function Information
output "load_test_function_name" {
  description = "Name of the load testing Cloud Function"
  value       = google_cloudfunctions_function.load_test_function.name
}

output "load_test_function_url" {
  description = "HTTPS trigger URL for the load testing function"
  value       = google_cloudfunctions_function.load_test_function.https_trigger_url
  sensitive   = false
}

output "function_service_account" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.perf_test_sa.email
}

# Storage Information
output "test_results_bucket" {
  description = "Name of the Cloud Storage bucket for test results"
  value       = google_storage_bucket.test_results.name
}

output "test_results_bucket_url" {
  description = "URL of the Cloud Storage bucket for test results"
  value       = google_storage_bucket.test_results.url
}

# Scheduler Information
output "daily_scheduler_job" {
  description = "Name of the daily performance test scheduler job"
  value       = google_cloud_scheduler_job.daily_perf_test.name
}

output "hourly_scheduler_job" {
  description = "Name of the hourly performance test scheduler job"
  value       = google_cloud_scheduler_job.hourly_perf_test.name
}

output "scheduler_time_zone" {
  description = "Time zone used for scheduler jobs"
  value       = google_cloud_scheduler_job.daily_perf_test.time_zone
}

# Monitoring Information
output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.perf_test_dashboard.id)}?project=${var.project_id}"
}

output "dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.perf_test_dashboard.id
}

output "alert_policy_response_time" {
  description = "Name of the response time alert policy"
  value       = google_monitoring_alert_policy.high_response_time.display_name
}

output "alert_policy_error_rate" {
  description = "Name of the error rate alert policy"
  value       = google_monitoring_alert_policy.high_error_rate.display_name
}

# Network and Security Information
output "firewall_rules" {
  description = "Names of the created firewall rules"
  value = [
    google_compute_firewall.allow_health_check.name,
    google_compute_firewall.allow_http.name
  ]
}

output "health_check_name" {
  description = "Name of the HTTP health check"
  value       = google_compute_health_check.app_health_check.name
}

# Configuration Information
output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone"
  value       = var.zone
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Resource Naming Information
output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Testing Commands
output "manual_test_command" {
  description = "Command to manually trigger a performance test"
  value       = <<-EOT
    curl -X POST "${google_cloudfunctions_function.load_test_function.https_trigger_url}" \
      -H "Content-Type: application/json" \
      -d '{
        "target_url": "http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}",
        "duration_seconds": 120,
        "concurrent_users": 15,
        "requests_per_second": 8,
        "project_id": "${var.project_id}",
        "bucket_name": "${google_storage_bucket.test_results.name}"
      }'
  EOT
}

output "test_verification_commands" {
  description = "Commands to verify the performance testing setup"
  value       = {
    check_load_balancer = "curl -s http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}"
    check_health        = "curl -s http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}/health"
    list_instances      = "gcloud compute instance-groups managed list-instances ${google_compute_region_instance_group_manager.app_group.name} --region=${var.region}"
    check_function      = "gcloud functions describe ${google_cloudfunctions_function.load_test_function.name} --region=${var.region}"
    list_scheduler_jobs = "gcloud scheduler jobs list --location=${var.region}"
    check_bucket        = "gsutil ls gs://${google_storage_bucket.test_results.name}/"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value       = {
    delete_scheduler_jobs = [
      "gcloud scheduler jobs delete ${google_cloud_scheduler_job.daily_perf_test.name} --location=${var.region} --quiet",
      "gcloud scheduler jobs delete ${google_cloud_scheduler_job.hourly_perf_test.name} --location=${var.region} --quiet"
    ]
    delete_function = "gcloud functions delete ${google_cloudfunctions_function.load_test_function.name} --region=${var.region} --quiet"
    delete_bucket   = "gsutil -m rm -r gs://${google_storage_bucket.test_results.name}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for different usage patterns"
  value = {
    light_usage = {
      description = "Hourly light tests (5 users, 5 req/s, 1 min) + daily tests (20 users, 10 req/s, 5 min)"
      compute     = "~$30-50/month (2-10 instances)"
      functions   = "~$1-5/month"
      storage     = "~$1-3/month"
      networking  = "~$5-15/month"
      monitoring  = "Free tier"
      total       = "~$37-73/month"
    }
    moderate_usage = {
      description = "More frequent testing with higher loads"
      compute     = "~$60-100/month"
      functions   = "~$5-15/month"
      storage     = "~$3-10/month"
      networking  = "~$15-30/month"
      monitoring  = "~$5-10/month"
      total       = "~$88-165/month"
    }
    note = "Costs vary based on region, actual usage patterns, and Google Cloud pricing changes"
  }
}

# Security Information
output "security_summary" {
  description = "Security configuration summary"
  value = {
    service_account     = "Dedicated service account with minimal required permissions"
    firewall_rules     = "Restricted to health check and HTTP traffic sources"
    bucket_access      = "Uniform bucket-level access enabled"
    function_security  = "HTTPS-only triggers with proper authentication"
    iam_permissions    = "Least privilege principle applied"
  }
}

# Performance Metrics Information
output "monitoring_metrics" {
  description = "Available monitoring metrics for analysis"
  value = {
    custom_metrics = [
      "custom.googleapis.com/performance_test/response_time_avg",
      "custom.googleapis.com/performance_test/requests_per_second",
      "custom.googleapis.com/performance_test/success_rate",
      "custom.googleapis.com/performance_test/total_requests"
    ]
    system_metrics = [
      "Load balancer request rate",
      "Backend response latency", 
      "Instance group size",
      "CPU utilization",
      "Health check status"
    ]
    dashboard_link = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.perf_test_dashboard.id)}?project=${var.project_id}"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait 5-10 minutes for all instances to become healthy",
    "2. Verify load balancer responds: curl http://${google_compute_global_forwarding_rule.app_forwarding_rule.ip_address}",
    "3. Run manual test using the provided command",
    "4. Check monitoring dashboard for metrics",
    "5. Review scheduled test results in Cloud Storage",
    "6. Configure notification channels for alerts if needed",
    "7. Customize test parameters in scheduler jobs as required"
  ]
}