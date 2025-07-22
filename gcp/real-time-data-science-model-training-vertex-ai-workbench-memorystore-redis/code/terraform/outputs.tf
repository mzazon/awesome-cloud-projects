# Project and Resource Information
output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region used for resources"
  value       = var.region
}

output "zone" {
  description = "The GCP zone used for resources"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

# Network Configuration
output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.ml_network.name
}

output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.ml_network.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.ml_subnet.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = google_compute_subnetwork.ml_subnet.id
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.ml_subnet.ip_cidr_range
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the ML training service account"
  value       = google_service_account.ml_training_sa.email
}

output "service_account_name" {
  description = "Name of the ML training service account"
  value       = google_service_account.ml_training_sa.name
}

# Redis Configuration
output "redis_instance_name" {
  description = "Name of the Redis instance"
  value       = google_redis_instance.ml_cache.name
}

output "redis_instance_id" {
  description = "ID of the Redis instance"
  value       = google_redis_instance.ml_cache.id
}

output "redis_host" {
  description = "Host IP address of the Redis instance"
  value       = google_redis_instance.ml_cache.host
  sensitive   = false
}

output "redis_port" {
  description = "Port number of the Redis instance"
  value       = google_redis_instance.ml_cache.port
}

output "redis_connection_string" {
  description = "Redis connection string"
  value       = "${google_redis_instance.ml_cache.host}:${google_redis_instance.ml_cache.port}"
}

output "redis_memory_size_gb" {
  description = "Memory size of the Redis instance in GB"
  value       = google_redis_instance.ml_cache.memory_size_gb
}

output "redis_tier" {
  description = "Service tier of the Redis instance"
  value       = google_redis_instance.ml_cache.tier
}

output "redis_version" {
  description = "Version of the Redis instance"
  value       = google_redis_instance.ml_cache.redis_version
}

output "redis_auth_enabled" {
  description = "Whether Redis AUTH is enabled"
  value       = google_redis_instance.ml_cache.auth_enabled
}

# Vertex AI Workbench Configuration
output "workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.name
}

output "workbench_instance_id" {
  description = "ID of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.id
}

output "workbench_proxy_uri" {
  description = "Proxy URI for accessing the Vertex AI Workbench"
  value       = google_workbench_instance.ml_workbench.proxy_uri
  sensitive   = false
}

output "workbench_jupyter_uri" {
  description = "Jupyter URI for the Vertex AI Workbench"
  value       = "https://console.cloud.google.com/vertex-ai/workbench/instances/${google_workbench_instance.ml_workbench.name}?project=${var.project_id}"
}

output "workbench_machine_type" {
  description = "Machine type of the Vertex AI Workbench instance"
  value       = var.workbench_machine_type
}

output "workbench_accelerator_type" {
  description = "Accelerator type of the Vertex AI Workbench instance"
  value       = var.workbench_accelerator_type
}

output "workbench_accelerator_count" {
  description = "Number of accelerators in the Vertex AI Workbench instance"
  value       = var.workbench_accelerator_count
}

# Cloud Storage Configuration
output "bucket_name" {
  description = "Name of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_bucket.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_bucket.self_link
}

output "bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_bucket.location
}

output "bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_bucket.storage_class
}

# Training Resources
output "training_script_location" {
  description = "Location of the training script in Cloud Storage"
  value       = "gs://${google_storage_bucket.ml_bucket.name}/${google_storage_bucket_object.training_script.name}"
}

output "jupyter_notebook_location" {
  description = "Location of the Jupyter notebook in Cloud Storage"
  value       = "gs://${google_storage_bucket.ml_bucket.name}/${google_storage_bucket_object.jupyter_notebook.name}"
}

output "dataset_folder_location" {
  description = "Location of the dataset folder in Cloud Storage"
  value       = "gs://${google_storage_bucket.ml_bucket.name}/${google_storage_bucket_object.dataset_folder.name}"
}

output "models_folder_location" {
  description = "Location of the models folder in Cloud Storage"
  value       = "gs://${google_storage_bucket.ml_bucket.name}/${google_storage_bucket_object.models_folder.name}"
}

# Monitoring Configuration
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.ml_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL of the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.ml_dashboard[0].id}?project=${var.project_id}" : null
}

# Environment Variables for Easy Access
output "environment_variables" {
  description = "Environment variables for ML training"
  value = {
    PROJECT_ID    = var.project_id
    REGION        = var.region
    ZONE          = var.zone
    REDIS_HOST    = google_redis_instance.ml_cache.host
    REDIS_PORT    = google_redis_instance.ml_cache.port
    BUCKET_NAME   = google_storage_bucket.ml_bucket.name
    NETWORK_NAME  = google_compute_network.ml_network.name
    SUBNET_NAME   = google_compute_subnetwork.ml_subnet.name
    SERVICE_ACCOUNT = google_service_account.ml_training_sa.email
  }
}

# Cloud Batch Configuration (for future use)
output "batch_job_configuration" {
  description = "Configuration for Cloud Batch jobs"
  value = {
    project_id       = var.project_id
    region          = var.region
    machine_type    = var.batch_machine_type
    cpu_milli       = var.batch_cpu_milli
    memory_mib      = var.batch_memory_mib
    task_count      = var.batch_task_count
    service_account = google_service_account.ml_training_sa.email
    network         = google_compute_network.ml_network.id
    subnet          = google_compute_subnetwork.ml_subnet.id
  }
}

# Connection Commands
output "redis_connection_command" {
  description = "Command to connect to Redis from Workbench"
  value       = "redis-cli -h ${google_redis_instance.ml_cache.host} -p ${google_redis_instance.ml_cache.port}"
}

output "gcloud_ssh_command" {
  description = "Command to SSH into the Workbench instance"
  value       = "gcloud compute ssh ${google_workbench_instance.ml_workbench.name} --zone=${var.zone} --project=${var.project_id}"
}

output "storage_access_command" {
  description = "Command to access the Cloud Storage bucket"
  value       = "gsutil ls gs://${google_storage_bucket.ml_bucket.name}/"
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    redis_instance = {
      name      = google_redis_instance.ml_cache.name
      host      = google_redis_instance.ml_cache.host
      port      = google_redis_instance.ml_cache.port
      memory_gb = google_redis_instance.ml_cache.memory_size_gb
      tier      = google_redis_instance.ml_cache.tier
    }
    workbench_instance = {
      name          = google_workbench_instance.ml_workbench.name
      machine_type  = var.workbench_machine_type
      accelerator   = "${var.workbench_accelerator_type} x${var.workbench_accelerator_count}"
      jupyter_uri   = "https://console.cloud.google.com/vertex-ai/workbench/instances/${google_workbench_instance.ml_workbench.name}?project=${var.project_id}"
    }
    storage_bucket = {
      name     = google_storage_bucket.ml_bucket.name
      location = google_storage_bucket.ml_bucket.location
      url      = google_storage_bucket.ml_bucket.url
    }
    network = {
      network_name = google_compute_network.ml_network.name
      subnet_name  = google_compute_subnetwork.ml_subnet.name
      subnet_cidr  = google_compute_subnetwork.ml_subnet.ip_cidr_range
    }
    service_account = {
      email = google_service_account.ml_training_sa.email
      name  = google_service_account.ml_training_sa.name
    }
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    redis_instance = "~$${var.redis_memory_size_gb * 0.054 * 24 * 30}"
    workbench_instance = "~$${var.workbench_machine_type == "n1-standard-4" ? 190 : 250} (varies by usage)"
    storage_bucket = "~$${var.bucket_storage_class == "STANDARD" ? 0.023 : 0.01}/GB stored"
    accelerator = "~$${var.workbench_accelerator_type == "NVIDIA_TESLA_T4" ? 0.35 : 0.50}/hour when active"
    total_estimated = "~$250-400/month (depending on usage patterns)"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps to use the deployed infrastructure"
  value = [
    "1. Access Vertex AI Workbench: ${google_workbench_instance.ml_workbench.proxy_uri}",
    "2. Open Jupyter Lab and create a new notebook",
    "3. Install required packages: pip install redis pandas scikit-learn",
    "4. Connect to Redis using: redis.Redis(host='${google_redis_instance.ml_cache.host}', port=${google_redis_instance.ml_cache.port})",
    "5. Access Cloud Storage bucket: gs://${google_storage_bucket.ml_bucket.name}",
    "6. Download sample notebook: gsutil cp gs://${google_storage_bucket.ml_bucket.name}/notebooks/ml_training_notebook.ipynb .",
    "7. View monitoring dashboard: https://console.cloud.google.com/monitoring/dashboards/custom/${var.enable_monitoring ? google_monitoring_dashboard.ml_dashboard[0].id : "N/A"}?project=${var.project_id}",
    "8. Test Redis connection: redis-cli -h ${google_redis_instance.ml_cache.host} -p ${google_redis_instance.ml_cache.port} ping"
  ]
}