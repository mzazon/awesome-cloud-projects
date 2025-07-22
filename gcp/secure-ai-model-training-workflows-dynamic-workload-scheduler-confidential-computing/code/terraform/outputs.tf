#===============================================================================
# PROJECT AND RESOURCE OUTPUTS
#===============================================================================

output "project_id" {
  description = "Google Cloud project ID used for the secure AI training infrastructure"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where compute resources are deployed"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

#===============================================================================
# NETWORKING OUTPUTS
#===============================================================================

output "network_name" {
  description = "Name of the VPC network created for secure AI training"
  value       = google_compute_network.training_network.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.training_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet for confidential computing instances"
  value       = google_compute_subnetwork.training_subnet.name
}

output "subnet_self_link" {
  description = "Self-link of the training subnet"
  value       = google_compute_subnetwork.training_subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR range of the training subnet"
  value       = google_compute_subnetwork.training_subnet.ip_cidr_range
}

#===============================================================================
# SECURITY AND ENCRYPTION OUTPUTS
#===============================================================================

output "kms_keyring_name" {
  description = "Name of the KMS keyring for training data encryption"
  value       = google_kms_key_ring.training_keyring.name
}

output "kms_keyring_id" {
  description = "Full resource ID of the KMS keyring"
  value       = google_kms_key_ring.training_keyring.id
}

output "kms_key_name" {
  description = "Name of the KMS encryption key"
  value       = google_kms_crypto_key.training_key.name
}

output "kms_key_id" {
  description = "Full resource ID of the KMS encryption key"
  value       = google_kms_crypto_key.training_key.id
}

output "kms_key_protection_level" {
  description = "Protection level of the KMS key (SOFTWARE or HSM)"
  value       = var.kms_key_protection_level
}

output "service_account_email" {
  description = "Email address of the service account for confidential computing"
  value       = google_service_account.training_service_account.email
}

output "service_account_name" {
  description = "Name of the service account for confidential computing"
  value       = google_service_account.training_service_account.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.training_service_account.unique_id
}

#===============================================================================
# STORAGE OUTPUTS
#===============================================================================

output "training_bucket_name" {
  description = "Name of the encrypted Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data_bucket.name
}

output "training_bucket_url" {
  description = "URL of the training data bucket"
  value       = google_storage_bucket.training_data_bucket.url
}

output "training_bucket_self_link" {
  description = "Self-link of the training data bucket"
  value       = google_storage_bucket.training_data_bucket.self_link
}

output "training_bucket_location" {
  description = "Location of the training data bucket"
  value       = google_storage_bucket.training_data_bucket.location
}

output "training_bucket_storage_class" {
  description = "Storage class of the training data bucket"
  value       = google_storage_bucket.training_data_bucket.storage_class
}

#===============================================================================
# COMPUTE AND DYNAMIC WORKLOAD SCHEDULER OUTPUTS
#===============================================================================

output "instance_template_name" {
  description = "Name of the confidential computing instance template"
  value       = google_compute_instance_template.confidential_training_template.name
}

output "instance_template_self_link" {
  description = "Self-link of the confidential computing instance template"
  value       = google_compute_instance_template.confidential_training_template.self_link
}

output "confidential_vm_name" {
  description = "Name of the confidential computing instance"
  value       = google_compute_instance.confidential_training_vm.name
}

output "confidential_vm_self_link" {
  description = "Self-link of the confidential computing instance"
  value       = google_compute_instance.confidential_training_vm.self_link
}

output "confidential_vm_internal_ip" {
  description = "Internal IP address of the confidential computing instance"
  value       = google_compute_instance.confidential_training_vm.network_interface[0].network_ip
}

output "confidential_vm_machine_type" {
  description = "Machine type of the confidential computing instance"
  value       = google_compute_instance.confidential_training_vm.machine_type
}

output "reservation_name" {
  description = "Name of the Dynamic Workload Scheduler reservation"
  value       = var.enable_dynamic_workload_scheduler ? google_compute_reservation.training_reservation[0].name : null
}

output "reservation_status" {
  description = "Status of the Dynamic Workload Scheduler reservation"
  value       = var.enable_dynamic_workload_scheduler ? google_compute_reservation.training_reservation[0].status : null
}

output "gpu_type" {
  description = "Type of GPU accelerator used for training"
  value       = var.accelerator_type
}

output "gpu_count" {
  description = "Number of GPU accelerators per instance"
  value       = var.accelerator_count
}

#===============================================================================
# SECURITY CONFIGURATION OUTPUTS
#===============================================================================

output "confidential_computing_enabled" {
  description = "Whether confidential computing is enabled"
  value       = var.enable_confidential_compute
}

output "secure_boot_enabled" {
  description = "Whether secure boot is enabled"
  value       = var.enable_secure_boot
}

output "vtpm_enabled" {
  description = "Whether virtual TPM is enabled"
  value       = var.enable_vtpm
}

output "integrity_monitoring_enabled" {
  description = "Whether integrity monitoring is enabled"
  value       = var.enable_integrity_monitoring
}

#===============================================================================
# MONITORING AND ALERTING OUTPUTS
#===============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_monitoring
}

output "notification_channel_id" {
  description = "ID of the monitoring notification channel (if email provided)"
  value       = var.enable_monitoring && var.monitoring_notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
}

output "attestation_alert_policy_id" {
  description = "ID of the confidential computing attestation failure alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.attestation_failure_alert[0].id : null
}

output "gpu_utilization_alert_policy_id" {
  description = "ID of the GPU utilization alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.gpu_utilization_alert[0].id : null
}

#===============================================================================
# AUDIT AND COMPLIANCE OUTPUTS
#===============================================================================

output "audit_logging_enabled" {
  description = "Whether audit logging is enabled for compliance"
  value       = var.enable_audit_logging
}

output "budget_alert_enabled" {
  description = "Whether budget alerts are enabled for cost management"
  value       = var.enable_budget_alerts
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = var.budget_amount
}

#===============================================================================
# CONNECTION AND ACCESS OUTPUTS
#===============================================================================

output "ssh_command" {
  description = "Command to SSH into the confidential computing instance via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap"
}

output "training_data_upload_command" {
  description = "Command to upload training data to the encrypted bucket"
  value       = "gsutil -m cp -r /path/to/training/data/* gs://${google_storage_bucket.training_data_bucket.name}/training/"
}

output "bucket_access_command" {
  description = "Command to list contents of the training data bucket"
  value       = "gsutil ls -la gs://${google_storage_bucket.training_data_bucket.name}/"
}

#===============================================================================
# VERTEX AI INTEGRATION OUTPUTS
#===============================================================================

output "vertex_ai_enabled" {
  description = "Whether Vertex AI training is enabled"
  value       = var.enable_vertex_ai_training
}

output "vertex_ai_region" {
  description = "Region for Vertex AI training jobs"
  value       = var.region
}

output "training_job_submit_command" {
  description = "Example command to submit a Vertex AI training job"
  value = "gcloud ai custom-jobs create --region=${var.region} --display-name=secure-training-job --config=training_job_config.yaml --service-account=${google_service_account.training_service_account.email}"
}

#===============================================================================
# ENVIRONMENT VALIDATION OUTPUTS
#===============================================================================

output "validation_script_path" {
  description = "Path to the environment validation script on the VM"
  value       = "/opt/training/scripts/validate_environment.py"
}

output "training_directory" {
  description = "Directory path for training data and scripts on the VM"
  value       = "/opt/training"
}

output "environment_ready_command" {
  description = "Command to validate the training environment is ready"
  value       = "gcloud compute ssh ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap --command='python3 /opt/training/scripts/validate_environment.py'"
}

#===============================================================================
# COST OPTIMIZATION OUTPUTS
#===============================================================================

output "dynamic_workload_scheduler_enabled" {
  description = "Whether Dynamic Workload Scheduler is enabled for cost optimization"
  value       = var.enable_dynamic_workload_scheduler
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure"
  value = {
    description = "Estimated costs are approximate and depend on usage patterns"
    compute_a2_highgpu_1g = "~$2,500-3,000/month for 24/7 usage"
    storage_standard      = "~$20-50/month for 1TB data"
    kms_operations       = "~$10-20/month for encryption operations"
    networking           = "~$10-30/month for internal traffic"
    monitoring_logging   = "~$20-50/month for logs and metrics"
    total_estimated      = "~$2,560-3,150/month (24/7) or ~$300-400/month (8hrs/day)"
    cost_optimization    = "Use Dynamic Workload Scheduler Flex Start for up to 70% savings"
  }
}

#===============================================================================
# TROUBLESHOOTING AND DEBUGGING OUTPUTS
#===============================================================================

output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the secure AI training environment"
  value = {
    check_vm_status           = "gcloud compute instances describe ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone}"
    check_gpu_status          = "gcloud compute ssh ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone} --tunnel-through-iap --command='nvidia-smi'"
    check_confidential_config = "gcloud compute instances describe ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone} --format='value(confidentialInstanceConfig.enableConfidentialCompute)'"
    view_startup_logs         = "gcloud compute instances get-serial-port-output ${google_compute_instance.confidential_training_vm.name} --zone=${var.zone}"
    check_service_account     = "gcloud iam service-accounts describe ${google_service_account.training_service_account.email}"
    test_bucket_access       = "gsutil ls gs://${google_storage_bucket.training_data_bucket.name}/"
    check_kms_key            = "gcloud kms keys describe ${google_kms_crypto_key.training_key.name} --location=${var.region} --keyring=${google_kms_key_ring.training_keyring.name}"
  }
}

#===============================================================================
# NEXT STEPS OUTPUTS
#===============================================================================

output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = {
    step_1 = "Upload training data: ${local.bucket_name}"
    step_2 = "SSH to VM and validate environment: Use ssh_command output"
    step_3 = "Configure Vertex AI training job with container image"
    step_4 = "Set up monitoring dashboards in Cloud Console"
    step_5 = "Review budget alerts and cost optimization settings"
    step_6 = "Test confidential computing attestation"
    step_7 = "Run sample training workload to validate setup"
  }
}