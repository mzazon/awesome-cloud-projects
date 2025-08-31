# Outputs for AI Training Optimization with Dynamic Workload Scheduler and Batch
# These outputs provide essential information for job submission, monitoring, and resource management

# Project and Location Information
output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for resource deployment"
  value       = var.zone
}

output "resource_suffix" {
  description = "The unique suffix applied to resource names"
  value       = local.suffix
}

# Storage Resources
output "training_data_bucket_name" {
  description = "Name of the Cloud Storage bucket for training data and scripts"
  value       = google_storage_bucket.training_data.name
}

output "training_data_bucket_url" {
  description = "URL of the Cloud Storage bucket for training data"
  value       = google_storage_bucket.training_data.url
}

output "training_script_path" {
  description = "Path to the training script in the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.training_data.name}/${var.training_script_path}"
}

output "bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.training_data.location
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account used for batch training jobs"
  value       = google_service_account.batch_training_sa.email
}

output "service_account_name" {
  description = "Name of the service account used for batch training jobs"
  value       = google_service_account.batch_training_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.batch_training_sa.unique_id
}

# Instance Template Information
output "instance_template_name" {
  description = "Name of the compute instance template for training jobs"
  value       = google_compute_instance_template.ai_training_template.name
}

output "instance_template_self_link" {
  description = "Self-link of the compute instance template"
  value       = google_compute_instance_template.ai_training_template.self_link
}

output "machine_type" {
  description = "Machine type configured for training instances"
  value       = var.machine_type
}

output "accelerator_configuration" {
  description = "GPU accelerator configuration for training instances"
  value = {
    type  = var.accelerator_type
    count = var.accelerator_count
  }
}

# Monitoring and Dashboard Information
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard for training visibility"
  value       = var.enable_monitoring_dashboard ? google_monitoring_dashboard.ai_training_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.ai_training_dashboard[0].id}?project=${var.project_id}" : null
}

output "gpu_utilization_alert_policy_name" {
  description = "Name of the GPU utilization alert policy"
  value       = var.enable_monitoring_dashboard ? google_monitoring_alert_policy.gpu_underutilization_alert[0].name : null
}

# Batch Job Configuration
output "batch_job_config_file" {
  description = "Path to the generated batch job configuration file"
  value       = local_file.batch_job_config.filename
}

output "batch_job_sample_command" {
  description = "Sample command to submit a batch training job"
  value = "gcloud batch jobs submit ai-training-job-$(date +%Y%m%d-%H%M%S) --location=${var.region} --config=${local_file.batch_job_config.filename}"
}

# Training Configuration
output "training_configuration" {
  description = "Complete training configuration summary"
  value = {
    container_image       = var.container_image
    max_training_duration = var.max_training_duration
    max_retry_count      = var.max_retry_count
    task_count           = var.task_count
    parallelism          = var.parallelism
    cpu_allocation_milli = var.cpu_milli
    memory_allocation_mib = var.memory_mib
  }
}

# Cost and Resource Management
output "cost_tracking_labels" {
  description = "Labels applied to all resources for cost tracking and organization"
  value       = local.common_labels
}

output "estimated_hourly_cost_usd" {
  description = "Estimated hourly cost in USD for running training jobs (approximate)"
  value = {
    note = "Cost estimates based on standard pricing, actual costs may vary"
    gpu_instance_hourly = "Approximately $0.75-$1.50 per hour for ${var.machine_type} with ${var.accelerator_type}"
    storage_monthly     = "Approximately $0.02-$0.04 per GB per month for Cloud Storage"
    monitoring_included = "Cloud Monitoring included in Google Cloud Free Tier limits"
  }
}

# Security and Access
output "security_configuration" {
  description = "Security settings applied to training infrastructure"
  value = {
    secure_boot_enabled          = var.enable_secure_boot
    vtpm_enabled                = var.enable_vtpm
    integrity_monitoring_enabled = var.enable_integrity_monitoring
    uniform_bucket_access       = true
    service_account_permissions = [
      "roles/storage.objectViewer",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter"
    ]
  }
}

# Deployment and Management Scripts
output "deployment_script_path" {
  description = "Path to the deployment script for submitting training jobs"
  value       = local_file.deploy_script.filename
}

output "cleanup_script_path" {
  description = "Path to the cleanup script for resource management"
  value       = local_file.cleanup_script.filename
}

# API and Service Information
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the training infrastructure"
  value       = var.enable_required_apis ? var.required_apis : []
}

# Network Configuration
output "network_configuration" {
  description = "Network configuration for training instances"
  value = {
    network_name    = var.network_name != "" ? var.network_name : "default"
    subnet_name     = var.subnet_name != "" ? var.subnet_name : "default"
    ip_forwarding   = var.enable_ip_forwarding
    external_ip     = true
    firewall_tags   = ["ai-training", "batch-job", "gpu-workload"]
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Essential commands for getting started with AI training"
  value = {
    submit_job = "gcloud batch jobs submit ai-training-job-$(date +%Y%m%d-%H%M%S) --location=${var.region} --config=${local_file.batch_job_config.filename}"
    
    monitor_job = "gcloud batch jobs describe JOB_NAME --location=${var.region}"
    
    view_logs = "gcloud logging read \"resource.type=batch_job AND resource.labels.job_id=JOB_NAME\" --limit=20"
    
    list_jobs = "gcloud batch jobs list --location=${var.region} --filter=\"labels.recipe=ai-training-optimization-scheduler-batch\""
    
    monitor_gpu = "gcloud monitoring metrics list --filter=\"metric.type:compute.googleapis.com/instance/accelerator\""
    
    check_costs = "gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID"
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "Google Cloud Console URLs for monitoring and management"
  value = {
    batch_jobs = "https://console.cloud.google.com/batch/jobs?project=${var.project_id}"
    
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.training_data.name}?project=${var.project_id}"
    
    monitoring_overview = "https://console.cloud.google.com/monitoring/overview?project=${var.project_id}"
    
    compute_instances = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
    
    service_accounts = "https://console.cloud.google.com/iam-admin/serviceaccounts?project=${var.project_id}"
    
    logs_explorer = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    
    billing_overview = "https://console.cloud.google.com/billing/overview?project=${var.project_id}"
  }
}

# Dynamic Workload Scheduler Information
output "dws_integration_info" {
  description = "Information about Dynamic Workload Scheduler integration"
  value = {
    scheduling_mode = "Flex Start Mode for enhanced resource obtainability"
    cost_savings    = "Up to 53% cost savings compared to on-demand pricing"
    optimization    = "Intelligent GPU scheduling with automatic resource allocation"
    
    benefits = [
      "Automatic queue management for GPU resources",
      "Cost-optimized resource provisioning",
      "Integration with Cloud Batch for reliable job execution",
      "Real-time monitoring and alerting capabilities"
    ]
    
    best_practices = [
      "Monitor GPU utilization to optimize resource usage",
      "Use appropriate machine types for workload requirements",
      "Implement proper retry logic for resilient training jobs",
      "Regular cost analysis using provided labels and monitoring"
    ]
  }
}

# Troubleshooting Information
output "troubleshooting_guide" {
  description = "Common troubleshooting commands and solutions"
  value = {
    check_quotas = "gcloud compute project-info describe --project=${var.project_id}"
    
    verify_apis = "gcloud services list --enabled --project=${var.project_id}"
    
    test_permissions = "gcloud auth list && gcloud config get-value project"
    
    check_gpu_availability = "gcloud compute accelerator-types list --zones=${var.zone}"
    
    validate_template = "gcloud compute instance-templates describe ${google_compute_instance_template.ai_training_template.name}"
    
    common_issues = {
      quota_exceeded    = "Check GPU quotas in Google Cloud Console and request increases if needed"
      permission_denied = "Verify service account has required IAM roles and APIs are enabled"
      job_failed       = "Check batch job logs using the view_logs command above"
      gpu_unavailable  = "Verify GPU availability in the selected zone and consider alternative zones"
    }
  }
}