# Project and Network Information
output "project_id" {
  description = "Google Cloud Project ID"
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

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.hpc_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.hpc_vpc.id
}

output "subnet_name" {
  description = "Name of the HPC subnet"
  value       = google_compute_subnetwork.hpc_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the HPC subnet"
  value       = google_compute_subnetwork.hpc_subnet.ip_cidr_range
}

# Storage Information
output "hpc_storage_bucket_name" {
  description = "Name of the HPC data storage bucket"
  value       = google_storage_bucket.hpc_data.name
}

output "hpc_storage_bucket_url" {
  description = "URL of the HPC data storage bucket"
  value       = google_storage_bucket.hpc_data.url
}

output "hpc_logs_bucket_name" {
  description = "Name of the HPC logs storage bucket"
  value       = google_storage_bucket.hpc_logs.name
}

output "storage_bucket_gsutil_uri" {
  description = "gsutil URI for the HPC data bucket"
  value       = "gs://${google_storage_bucket.hpc_data.name}"
}

# Compute Instance Information
output "hpc_instance_template_id" {
  description = "ID of the HPC instance template"
  value       = google_compute_instance_template.hpc_template.id
}

output "hpc_instance_group_manager_name" {
  description = "Name of the HPC managed instance group"
  value       = google_compute_instance_group_manager.hpc_mig.name
}

output "hpc_instance_group_manager_id" {
  description = "ID of the HPC managed instance group"
  value       = google_compute_instance_group_manager.hpc_mig.id
}

output "hpc_instance_count" {
  description = "Number of HPC compute instances"
  value       = var.hpc_instance_count
}

output "hpc_machine_type" {
  description = "Machine type used for HPC instances"
  value       = var.hpc_machine_type
}

# GPU Instance Information
output "gpu_instance_template_id" {
  description = "ID of the GPU instance template"
  value       = var.gpu_instance_count > 0 ? google_compute_instance_template.gpu_template[0].id : null
}

output "gpu_instance_group_manager_name" {
  description = "Name of the GPU managed instance group"
  value       = var.gpu_instance_count > 0 ? google_compute_instance_group_manager.gpu_mig[0].name : null
}

output "gpu_instance_group_manager_id" {
  description = "ID of the GPU managed instance group"
  value       = var.gpu_instance_count > 0 ? google_compute_instance_group_manager.gpu_mig[0].id : null
}

output "gpu_instance_count" {
  description = "Number of GPU compute instances"
  value       = var.gpu_instance_count
}

output "gpu_machine_type" {
  description = "Machine type used for GPU instances"
  value       = var.gpu_machine_type
}

output "gpu_type" {
  description = "Type of GPU accelerator"
  value       = var.gpu_type
}

output "gpu_count_per_instance" {
  description = "Number of GPUs per instance"
  value       = var.gpu_count
}

# Service Account Information
output "hpc_service_account_email" {
  description = "Email of the HPC compute service account"
  value       = google_service_account.hpc_compute.email
}

output "hpc_service_account_id" {
  description = "ID of the HPC compute service account"
  value       = google_service_account.hpc_compute.id
}

# Placement Policy Information
output "placement_policy_name" {
  description = "Name of the HPC placement policy"
  value       = google_compute_resource_policy.hpc_placement.name
}

output "placement_policy_id" {
  description = "ID of the HPC placement policy"
  value       = google_compute_resource_policy.hpc_placement.id
}

# Cloud Batch Information
output "batch_job_name" {
  description = "Name of the sample batch job"
  value       = var.enable_batch_jobs ? google_batch_job.hpc_spot_job[0].name : null
}

output "batch_job_id" {
  description = "ID of the sample batch job"
  value       = var.enable_batch_jobs ? google_batch_job.hpc_spot_job[0].id : null
}

output "batch_task_count" {
  description = "Number of tasks in batch jobs"
  value       = var.batch_task_count
}

output "batch_parallelism" {
  description = "Parallelism level for batch jobs"
  value       = var.batch_parallelism
}

# GPU Reservation Information
output "gpu_reservation_name" {
  description = "Name of the GPU reservation"
  value       = var.enable_gpu_reservation && var.gpu_instance_count > 0 ? google_compute_reservation.gpu_reservation[0].name : null
}

output "gpu_reservation_id" {
  description = "ID of the GPU reservation"
  value       = var.enable_gpu_reservation && var.gpu_instance_count > 0 ? google_compute_reservation.gpu_reservation[0].id : null
}

# Monitoring Information
output "monitoring_dashboard_name" {
  description = "Name of the monitoring dashboard"
  value       = var.enable_monitoring ? jsondecode(google_monitoring_dashboard.hpc_dashboard[0].dashboard_json).displayName : null
}

output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.hpc_dashboard[0].id : null
}

output "budget_alert_name" {
  description = "Name of the budget alert"
  value       = var.enable_monitoring && length(data.google_billing_account.current) > 0 ? google_billing_budget.hpc_budget[0].display_name : null
}

output "budget_alert_id" {
  description = "ID of the budget alert"
  value       = var.enable_monitoring && length(data.google_billing_account.current) > 0 ? google_billing_budget.hpc_budget[0].name : null
}

output "budget_pubsub_topic" {
  description = "Pub/Sub topic for budget alerts"
  value       = var.enable_monitoring ? google_pubsub_topic.budget_alerts[0].name : null
}

# Health Check Information
output "hpc_health_check_name" {
  description = "Name of the HPC health check"
  value       = google_compute_health_check.hpc_health.name
}

output "gpu_health_check_name" {
  description = "Name of the GPU health check"
  value       = var.gpu_instance_count > 0 ? google_compute_health_check.gpu_health[0].name : null
}

# Firewall Rules Information
output "firewall_internal_rule_name" {
  description = "Name of the internal firewall rule"
  value       = google_compute_firewall.hpc_internal.name
}

output "firewall_ssh_rule_name" {
  description = "Name of the SSH firewall rule"
  value       = google_compute_firewall.hpc_ssh.name
}

# Random Suffix for Resource Identification
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Deployment Status
output "deployment_summary" {
  description = "Summary of the HPC deployment"
  value = {
    project_id            = var.project_id
    region               = var.region
    zone                 = var.zone
    vpc_network          = google_compute_network.hpc_vpc.name
    hpc_storage_bucket   = google_storage_bucket.hpc_data.name
    hpc_instance_count   = var.hpc_instance_count
    gpu_instance_count   = var.gpu_instance_count
    batch_jobs_enabled   = var.enable_batch_jobs
    monitoring_enabled   = var.enable_monitoring
    gpu_reservation_enabled = var.enable_gpu_reservation && var.gpu_instance_count > 0
    resource_suffix      = random_id.suffix.hex
  }
}

# Access Instructions
output "access_instructions" {
  description = "Instructions for accessing the HPC cluster"
  value = {
    ssh_command = "gcloud compute ssh --zone=${var.zone} --tunnel-through-iap <instance-name>"
    bucket_access = "gsutil ls gs://${google_storage_bucket.hpc_data.name}"
    batch_job_list = "gcloud batch jobs list --location=${var.region}"
    monitoring_console = "https://console.cloud.google.com/monitoring/dashboards"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the HPC deployment"
  value = {
    use_preemptible_instances = "Consider using preemptible instances for fault-tolerant workloads"
    schedule_gpu_reservations = "Schedule GPU reservations only when needed to avoid unnecessary costs"
    monitor_storage_usage = "Monitor storage lifecycle policies and clean up unnecessary data"
    use_committed_use_discounts = "Consider committed use discounts for predictable workloads"
    scale_down_when_idle = "Scale down instance groups when not running active workloads"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    service_account = google_service_account.hpc_compute.email
    private_instances = "Instances use private IPs with Cloud NAT for outbound access"
    firewall_rules = [
      google_compute_firewall.hpc_internal.name,
      google_compute_firewall.hpc_ssh.name
    ]
    storage_encryption = "Storage buckets use Google-managed encryption by default"
    oslogin_enabled = "OS Login is enabled for centralized SSH key management"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Verify all instances are running: gcloud compute instances list --filter='name~(hpc-worker|gpu-worker)'",
    "Test storage access: gsutil ls gs://${google_storage_bucket.hpc_data.name}",
    "Monitor batch jobs: gcloud batch jobs list --location=${var.region}",
    "Access monitoring dashboard: https://console.cloud.google.com/monitoring/dashboards",
    "Review cost in billing console: https://console.cloud.google.com/billing",
    "Configure additional monitoring alerts as needed",
    "Set up data preprocessing workflows using Cloud Functions or Dataflow",
    "Implement backup strategies for critical data"
  ]
}