# Outputs for GCP OS Patch Management Infrastructure
# This file defines the outputs that will be displayed after successful deployment

output "project_id" {
  description = "Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources were created"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where VM instances were created"
  value       = var.zone
}

output "vm_instances" {
  description = "Information about created VM instances"
  value = {
    for instance in google_compute_instance.patch_test_vms : instance.name => {
      name              = instance.name
      machine_type      = instance.machine_type
      zone             = instance.zone
      internal_ip      = instance.network_interface[0].network_ip
      external_ip      = length(instance.network_interface[0].access_config) > 0 ? instance.network_interface[0].access_config[0].nat_ip : "None"
      status           = instance.current_status
      self_link        = instance.self_link
      os_config_enabled = lookup(instance.metadata, "enable-osconfig", "false")
    }
  }
}

output "network_details" {
  description = "Network infrastructure details"
  value = {
    network_name      = google_compute_network.patch_network.name
    network_self_link = google_compute_network.patch_network.self_link
    subnet_name       = google_compute_subnetwork.patch_subnet.name
    subnet_cidr       = google_compute_subnetwork.patch_subnet.ip_cidr_range
    subnet_self_link  = google_compute_subnetwork.patch_subnet.self_link
    firewall_rules    = [for rule in google_compute_firewall.patch_firewall : rule.name]
  }
}

output "cloud_storage_bucket" {
  description = "Cloud Storage bucket for patch scripts"
  value = {
    name         = google_storage_bucket.patch_scripts.name
    url          = google_storage_bucket.patch_scripts.url
    self_link    = google_storage_bucket.patch_scripts.self_link
    location     = google_storage_bucket.patch_scripts.location
    storage_class = google_storage_bucket.patch_scripts.storage_class
  }
}

output "patch_scripts" {
  description = "Information about uploaded patch scripts"
  value = {
    pre_patch_script = {
      name = google_storage_bucket_object.pre_patch_script.name
      md5hash = google_storage_bucket_object.pre_patch_script.md5hash
      self_link = google_storage_bucket_object.pre_patch_script.self_link
    }
    post_patch_script = {
      name = google_storage_bucket_object.post_patch_script.name
      md5hash = google_storage_bucket_object.post_patch_script.md5hash
      self_link = google_storage_bucket_object.post_patch_script.self_link
    }
  }
}

output "cloud_function" {
  description = "Cloud Function for patch orchestration"
  value = {
    name         = google_cloudfunctions_function.patch_orchestrator.name
    trigger_url  = google_cloudfunctions_function.patch_orchestrator.https_trigger_url
    status       = google_cloudfunctions_function.patch_orchestrator.status
    runtime      = google_cloudfunctions_function.patch_orchestrator.runtime
    entry_point  = google_cloudfunctions_function.patch_orchestrator.entry_point
    source_bucket = google_cloudfunctions_function.patch_orchestrator.source_archive_bucket
    source_object = google_cloudfunctions_function.patch_orchestrator.source_archive_object
  }
}

output "cloud_scheduler_job" {
  description = "Cloud Scheduler job for automated patch deployment"
  value = {
    name         = google_cloud_scheduler_job.patch_scheduler.name
    schedule     = google_cloud_scheduler_job.patch_scheduler.schedule
    time_zone    = google_cloud_scheduler_job.patch_scheduler.time_zone
    state        = google_cloud_scheduler_job.patch_scheduler.state
    description  = google_cloud_scheduler_job.patch_scheduler.description
    target_uri   = google_cloud_scheduler_job.patch_scheduler.http_target[0].uri
  }
}

output "service_account" {
  description = "Service account for patch management operations"
  value = var.create_service_account ? {
    name         = google_service_account.patch_management_sa[0].name
    email        = google_service_account.patch_management_sa[0].email
    display_name = google_service_account.patch_management_sa[0].display_name
    unique_id    = google_service_account.patch_management_sa[0].unique_id
    roles        = [
      "roles/compute.osAdminLogin",
      "roles/osconfig.patchJobExecutor",
      "roles/compute.instanceAdmin.v1",
      "roles/storage.objectViewer",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter"
    ]
  } : null
}

output "monitoring_dashboard" {
  description = "Cloud Monitoring dashboard for patch management"
  value = var.enable_monitoring ? {
    name         = google_monitoring_dashboard.patch_management[0].display_name
    dashboard_id = google_monitoring_dashboard.patch_management[0].id
  } : null
}

output "alert_policies" {
  description = "Alert policies for patch management monitoring"
  value = var.enable_monitoring ? {
    patch_failure_alert = {
      name         = google_monitoring_alert_policy.patch_failure_alert[0].display_name
      policy_id    = google_monitoring_alert_policy.patch_failure_alert[0].name
      enabled      = google_monitoring_alert_policy.patch_failure_alert[0].enabled
      conditions   = length(google_monitoring_alert_policy.patch_failure_alert[0].conditions)
    }
    instance_down_alert = {
      name         = google_monitoring_alert_policy.instance_down_alert[0].display_name
      policy_id    = google_monitoring_alert_policy.instance_down_alert[0].name
      enabled      = google_monitoring_alert_policy.instance_down_alert[0].enabled
      conditions   = length(google_monitoring_alert_policy.instance_down_alert[0].conditions)
    }
  } : null
}

output "enabled_apis" {
  description = "APIs enabled for the project"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

output "patch_management_instructions" {
  description = "Instructions for using the patch management system"
  value = <<-EOT
    ## Patch Management System Deployed Successfully!
    
    ### Manual Patch Deployment:
    1. Trigger patch deployment via Cloud Functions:
       curl -X POST "${google_cloudfunctions_function.patch_orchestrator.https_trigger_url}"
    
    2. Or via Cloud Scheduler:
       gcloud scheduler jobs run ${google_cloud_scheduler_job.patch_scheduler.name} --location=${var.region}
    
    ### Monitoring:
    - View patch job status: gcloud compute os-config patch-jobs list
    - Check VM inventory: gcloud compute os-config inventories list
    - Monitor dashboard: https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.patch_management[0].id}
    
    ### SSH Access to VMs:
    %{for instance in google_compute_instance.patch_test_vms}
    - ${instance.name}: gcloud compute ssh ${instance.name} --zone=${instance.zone}
    %{endfor}
    
    ### Patch Scripts Location:
    - Pre-patch: gs://${google_storage_bucket.patch_scripts.name}/pre-patch-backup.sh
    - Post-patch: gs://${google_storage_bucket.patch_scripts.name}/post-patch-validation.sh
    
    ### Next Steps:
    1. Test manual patch deployment using the Cloud Function trigger URL
    2. Review monitoring dashboard for patch compliance metrics
    3. Customize patch scripts in Cloud Storage as needed
    4. Configure notification channels for alerts
    EOT
}

output "cleanup_instructions" {
  description = "Instructions for cleaning up resources"
  value = <<-EOT
    ## Cleanup Instructions
    
    To remove all resources created by this deployment:
    
    1. Run Terraform destroy:
       terraform destroy -auto-approve
    
    2. Or manually delete resources:
       - Delete VM instances: gcloud compute instances delete ${join(" ", [for instance in google_compute_instance.patch_test_vms : instance.name])} --zone=${var.zone}
       - Delete Cloud Function: gcloud functions delete ${google_cloudfunctions_function.patch_orchestrator.name} --region=${var.region}
       - Delete Cloud Scheduler job: gcloud scheduler jobs delete ${google_cloud_scheduler_job.patch_scheduler.name} --location=${var.region}
       - Delete Cloud Storage bucket: gsutil -m rm -r gs://${google_storage_bucket.patch_scripts.name}
       - Delete monitoring resources via Console
    
    3. Verify cleanup:
       gcloud compute instances list --filter="name:patch-test-vm-*"
       gcloud functions list --filter="name:${google_cloudfunctions_function.patch_orchestrator.name}"
       gcloud scheduler jobs list --filter="name:${google_cloud_scheduler_job.patch_scheduler.name}"
    EOT
}

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = <<-EOT
    ## Estimated Monthly Costs (USD)
    
    Based on us-central1 pricing (prices may vary by region):
    
    ### Compute Engine:
    - VM Instances (${var.vm_instance_count}x ${var.vm_machine_type}): ~$${var.vm_instance_count * 24.27} - $${var.vm_instance_count * 48.54}/month
    - Boot Disks (${var.vm_instance_count}x ${var.vm_boot_disk_size}GB): ~$${var.vm_instance_count * var.vm_boot_disk_size * 0.04}/month
    
    ### Cloud Storage:
    - Patch Scripts Storage: ~$0.02/month (minimal usage)
    
    ### Cloud Functions:
    - Function Execution: ~$0.40/million requests (minimal for scheduled patches)
    
    ### Cloud Scheduler:
    - Scheduler Jobs: $0.10/job/month
    
    ### Cloud Monitoring:
    - Metrics & Dashboards: Free tier covers basic usage
    
    ### Total Estimated Cost: ~$${var.vm_instance_count * 24.67 + var.vm_instance_count * var.vm_boot_disk_size * 0.04 + 0.12} - $${var.vm_instance_count * 48.94 + var.vm_instance_count * var.vm_boot_disk_size * 0.04 + 0.12}/month
    
    Note: Costs may vary based on actual usage, region, and Google Cloud pricing changes.
    VM Manager and OS Config services are included at no additional cost.
    EOT
}