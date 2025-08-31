# Project and region information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone"
  value       = var.zone
}

# Resource naming outputs
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}

# Pub/Sub resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for task queue"
  value       = google_pubsub_topic.task_queue.name
}

output "pubsub_topic_id" {
  description = "Full ID of the Pub/Sub topic"
  value       = google_pubsub_topic.task_queue.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for workers"
  value       = google_pubsub_subscription.worker_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.worker_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.dead_letter.name
}

output "dead_letter_topic_id" {
  description = "Full ID of the dead letter queue topic"
  value       = google_pubsub_topic.dead_letter.id
}

# Cloud Storage resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for file processing"
  value       = google_storage_bucket.task_files.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.task_files.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.task_files.self_link
}

output "logs_bucket_name" {
  description = "Name of the Cloud Storage bucket for logs (if logging enabled)"
  value       = var.enable_cloud_logging ? google_storage_bucket.logs[0].name : null
}

# Service accounts
output "worker_service_account_email" {
  description = "Email of the worker service account"
  value       = var.create_service_accounts ? google_service_account.worker_sa[0].email : var.existing_worker_service_account
}

output "worker_service_account_name" {
  description = "Name of the worker service account"
  value       = var.create_service_accounts ? google_service_account.worker_sa[0].name : null
}

output "api_service_account_email" {
  description = "Email of the API service account"
  value       = var.create_service_accounts ? google_service_account.api_sa[0].email : var.existing_api_service_account
}

output "api_service_account_name" {
  description = "Name of the API service account"
  value       = var.create_service_accounts ? google_service_account.api_sa[0].name : null
}

# Cloud Run Job
output "cloud_run_job_name" {
  description = "Name of the Cloud Run Job for background processing"
  value       = google_cloud_run_v2_job.background_worker.name
}

output "cloud_run_job_id" {
  description = "Full ID of the Cloud Run Job"
  value       = google_cloud_run_v2_job.background_worker.id
}

output "cloud_run_job_location" {
  description = "Location of the Cloud Run Job"
  value       = google_cloud_run_v2_job.background_worker.location
}

# Cloud Run API Service
output "cloud_run_api_service_name" {
  description = "Name of the Cloud Run API service"
  value       = google_cloud_run_v2_service.task_api.name
}

output "cloud_run_api_service_id" {
  description = "Full ID of the Cloud Run API service"
  value       = google_cloud_run_v2_service.task_api.id
}

output "cloud_run_api_service_url" {
  description = "URL of the Cloud Run API service"
  value       = google_cloud_run_v2_service.task_api.uri
}

output "cloud_run_api_service_location" {
  description = "Location of the Cloud Run API service"
  value       = google_cloud_run_v2_service.task_api.location
}

# Container images
output "worker_container_image" {
  description = "Container image path for the worker"
  value       = local.worker_image
}

output "api_container_image" {
  description = "Container image path for the API service"
  value       = local.api_image
}

# Configuration for testing and deployment
output "api_endpoints" {
  description = "API endpoints for task submission"
  value = {
    health           = "${google_cloud_run_v2_service.task_api.uri}/health"
    submit_task      = "${google_cloud_run_v2_service.task_api.uri}/submit-task"
    submit_file_task = "${google_cloud_run_v2_service.task_api.uri}/submit-file-task"
    submit_data_task = "${google_cloud_run_v2_service.task_api.uri}/submit-data-task"
  }
}

# Deployment commands
output "deployment_commands" {
  description = "Commands for building and deploying the application"
  value = {
    build_worker_image = "gcloud builds submit --tag ${local.worker_image} ./background-worker/"
    build_api_image    = "gcloud builds submit --tag ${local.api_image} ./task-api/"
    execute_job        = "gcloud run jobs execute ${google_cloud_run_v2_job.background_worker.name} --region=${var.region} --wait"
    update_job_image   = "gcloud run jobs replace ${google_cloud_run_v2_job.background_worker.name} --image=${local.worker_image} --region=${var.region}"
    update_api_image   = "gcloud run services update ${google_cloud_run_v2_service.task_api.name} --image=${local.api_image} --region=${var.region}"
  }
}

# Testing commands
output "testing_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    test_api_health = "curl ${google_cloud_run_v2_service.task_api.uri}/health"
    submit_file_task = jsonencode({
      command = "curl -X POST"
      url     = "${google_cloud_run_v2_service.task_api.uri}/submit-file-task"
      headers = "-H 'Content-Type: application/json'"
      data    = "-d '{\"filename\": \"test-document.pdf\", \"processing_time\": 3}'"
    })
    submit_data_task = jsonencode({
      command = "curl -X POST"
      url     = "${google_cloud_run_v2_service.task_api.uri}/submit-data-task"
      headers = "-H 'Content-Type: application/json'"
      data    = "-d '{\"dataset_size\": 500, \"transformation\": \"aggregation\"}'"
    })
    check_subscription = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.worker_subscription.name} --auto-ack --limit=5"
    list_bucket_files  = "gsutil ls -r gs://${google_storage_bucket.task_files.name}/"
  }
}

# Monitoring and logging
output "monitoring_dashboard_url" {
  description = "URL to view the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.task_processing.id}?project=${var.project_id}"
}

output "logs_explorer_url" {
  description = "URL to view logs in Cloud Logging"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%20OR%20resource.type%3D%22cloud_run_job%22%20OR%20resource.type%3D%22pubsub_topic%22%20OR%20resource.type%3D%22pubsub_subscription%22?project=${var.project_id}"
}

# Resource cleanup commands
output "cleanup_commands" {
  description = "Commands for cleaning up resources manually if needed"
  value = {
    delete_job         = "gcloud run jobs delete ${google_cloud_run_v2_job.background_worker.name} --region=${var.region} --quiet"
    delete_api_service = "gcloud run services delete ${google_cloud_run_v2_service.task_api.name} --region=${var.region} --quiet"
    delete_subscription = "gcloud pubsub subscriptions delete ${google_pubsub_subscription.worker_subscription.name}"
    delete_topics      = "gcloud pubsub topics delete ${google_pubsub_topic.task_queue.name} && gcloud pubsub topics delete ${google_pubsub_topic.dead_letter.name}"
    delete_bucket      = "gsutil -m rm -r gs://${google_storage_bucket.task_files.name}"
  }
}

# Important notes for users
output "important_notes" {
  description = "Important information for deployment and usage"
  value = {
    container_images = "You need to build and push container images before the Cloud Run services will work properly. Use the build commands provided in deployment_commands output."
    authentication   = var.allow_unauthenticated ? "API service allows unauthenticated access. Consider setting allow_unauthenticated=false for production environments." : "API service requires authentication. Ensure proper IAM permissions are configured."
    cost_optimization = "Cloud Run services scale to zero when not in use, minimizing costs. Monitor usage patterns and adjust resource limits as needed."
    security_considerations = "Review and adjust IAM permissions based on your security requirements. Consider using VPC connectors for private network access."
    backup_strategy = "Consider implementing backup strategies for your Cloud Storage bucket and configuring cross-region replication for critical data."
  }
}