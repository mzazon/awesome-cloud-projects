# Outputs for multi-tenant resource scheduling infrastructure
# These outputs provide important information for accessing and managing the deployed resources

# Project and Environment Information
output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "The unique resource suffix used for naming"
  value       = local.resource_suffix
}

# Cloud Filestore Information
output "filestore_instance_name" {
  description = "Name of the Cloud Filestore instance"
  value       = google_filestore_instance.tenant_storage.name
}

output "filestore_ip_address" {
  description = "IP address of the Cloud Filestore instance for mounting"
  value       = google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]
}

output "filestore_share_name" {
  description = "Name of the file share on the Filestore instance"
  value       = var.filestore_share_name
}

output "filestore_capacity_gb" {
  description = "Capacity of the Cloud Filestore instance in GB"
  value       = var.filestore_capacity_gb
}

output "filestore_mount_target" {
  description = "Complete mount target for accessing the Filestore share"
  value       = "${google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]}:/${var.filestore_share_name}"
}

# Cloud Function Information
output "function_name" {
  description = "Name of the resource scheduler Cloud Function"
  value       = google_cloudfunctions_function.resource_scheduler.name
}

output "function_url" {
  description = "HTTPS trigger URL for the resource scheduler function"
  value       = google_cloudfunctions_function.resource_scheduler.https_trigger_url
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = google_cloudfunctions_function.resource_scheduler.region
}

# Cloud Scheduler Information
output "scheduler_jobs" {
  description = "List of created Cloud Scheduler jobs"
  value = var.enable_scheduled_jobs ? {
    cleanup_job = {
      name     = google_cloud_scheduler_job.tenant_cleanup[0].name
      schedule = google_cloud_scheduler_job.tenant_cleanup[0].schedule
      timezone = google_cloud_scheduler_job.tenant_cleanup[0].time_zone
    }
    quota_monitor_job = {
      name     = google_cloud_scheduler_job.quota_monitor[0].name
      schedule = google_cloud_scheduler_job.quota_monitor[0].schedule
      timezone = google_cloud_scheduler_job.quota_monitor[0].time_zone
    }
    tenant_a_job = {
      name     = google_cloud_scheduler_job.tenant_a_processing[0].name
      schedule = google_cloud_scheduler_job.tenant_a_processing[0].schedule
      timezone = google_cloud_scheduler_job.tenant_a_processing[0].time_zone
    }
  } : {}
}

# Monitoring Information
output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.tenant_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the quota violation alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.quota_violation[0].display_name : null
}

# Storage Information
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Network Information
output "network_name" {
  description = "Name of the VPC network used by resources"
  value       = var.network_name
}

# Tenant Configuration
output "tenant_quotas" {
  description = "Resource quotas configured for each tenant"
  value       = var.tenant_quotas
}

output "quota_alert_threshold" {
  description = "Threshold percentage for quota violation alerts"
  value       = var.quota_alert_threshold
}

# Access Instructions
output "filestore_mount_instructions" {
  description = "Instructions for mounting the Filestore share"
  value = <<-EOT
    To mount the Filestore share on a Compute Engine instance:
    
    1. Install NFS client:
       sudo apt-get update && sudo apt-get install nfs-common
    
    2. Create mount point:
       sudo mkdir -p /mnt/tenant_storage
    
    3. Mount the share:
       sudo mount -t nfs -o nfsvers=3 ${google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]}:/${var.filestore_share_name} /mnt/tenant_storage
    
    4. For persistent mounting, add to /etc/fstab:
       ${google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]}:/${var.filestore_share_name} /mnt/tenant_storage nfs nfsvers=3 0 0
  EOT
}

output "function_testing_commands" {
  description = "Example commands for testing the Cloud Function"
  value = <<-EOT
    Test the resource scheduler function using curl:
    
    1. Test tenant A resource request:
       curl -X POST "${google_cloudfunctions_function.resource_scheduler.https_trigger_url}" \
            -H "Content-Type: application/json" \
            -d '{
                "tenant_id": "tenant_a",
                "resource_type": "compute",
                "capacity": 3,
                "duration": 4
            }'
    
    2. Test quota violation:
       curl -X POST "${google_cloudfunctions_function.resource_scheduler.https_trigger_url}" \
            -H "Content-Type: application/json" \
            -d '{
                "tenant_id": "tenant_c",
                "resource_type": "compute",
                "capacity": 15,
                "duration": 1
            }'
    
    3. Check scheduler job status:
       gcloud scheduler jobs list --location=${var.region}
  EOT
}

# Security Information
output "security_considerations" {
  description = "Important security considerations for this deployment"
  value = <<-EOT
    Security Configuration Notes:
    
    1. Function Authentication: ${var.allow_unauthenticated_function ? "⚠️  Function allows unauthenticated access - NOT recommended for production" : "✅ Function requires authentication"}
    
    2. Service Account: Uses minimal permissions principle with roles:
       - roles/monitoring.metricWriter
       - roles/logging.logWriter  
       - roles/file.editor
    
    3. Network: Resources deployed in ${var.network_name} network
    
    4. Recommendations for production:
       - Set allow_unauthenticated_function = false
       - Use custom service account with minimal permissions
       - Enable VPC Service Controls for additional security
       - Implement proper authentication for function access
       - Use Cloud IAM for tenant access control
  EOT
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = <<-EOT
    Estimated Monthly Costs (USD, approximate):
    
    Cloud Filestore (${var.filestore_tier}, ${var.filestore_capacity_gb}GB): 
      - BASIC_HDD: ~$20-40/month
      - BASIC_SSD: ~$120-200/month
    
    Cloud Function (${var.function_memory_mb}MB):
      - Low usage: ~$0-5/month
      - Moderate usage: ~$5-20/month
    
    Cloud Scheduler (${var.enable_scheduled_jobs ? "3 jobs" : "0 jobs"}):
      - ~$0.10-1/month
    
    Cloud Storage (function source):
      - ~$0.02-0.20/month
    
    Cloud Monitoring:
      - Basic monitoring: Free tier
      - Custom metrics: ~$0.01-1/month
    
    Total Estimated: $20-250/month depending on tier and usage
    
    Note: Costs vary by region and actual usage patterns.
  EOT
}