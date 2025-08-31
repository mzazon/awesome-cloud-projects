# Core infrastructure outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the Cloud Function that processes tasks"
  value       = google_cloudfunctions2_function.task_processor.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.task_processor.service_config[0].uri
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email address of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Cloud Tasks queue outputs
output "queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.background_tasks.name
}

output "queue_id" {
  description = "Full resource ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.background_tasks.id
}

output "queue_location" {
  description = "Location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.background_tasks.location
}

output "dead_letter_queue_name" {
  description = "Name of the dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? google_cloud_tasks_queue.dead_letter_queue[0].name : null
}

# Cloud Storage outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed files"
  value       = google_storage_bucket.task_results.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.task_results.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.task_results.self_link
}

# Monitoring outputs
output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard (if enabled)"
  value = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.task_queue_dashboard[0].id}?project=${var.project_id}" : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if created)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

# Task creation helper outputs
output "task_creation_command" {
  description = "Example command to create a task using gcloud CLI"
  value = <<-EOT
    gcloud tasks create-http-task task-$(date +%s) \
      --queue=${google_cloud_tasks_queue.background_tasks.name} \
      --location=${var.region} \
      --url=${google_cloudfunctions2_function.task_processor.service_config[0].uri} \
      --method=POST \
      --header=Content-Type:application/json \
      --body-content='{"task_type":"process_file","filename":"example.txt","content":"Sample content"}'
  EOT
}

output "python_client_example" {
  description = "Python code example for creating tasks programmatically"
  value = <<-EOT
    # Install required package: pip install google-cloud-tasks
    
    from google.cloud import tasks_v2
    import json
    
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path('${var.project_id}', '${var.region}', '${google_cloud_tasks_queue.background_tasks.name}')
    
    task = {
        'http_request': {
            'http_method': tasks_v2.HttpMethod.POST,
            'url': '${google_cloudfunctions2_function.task_processor.service_config[0].uri}',
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'task_type': 'process_file',
                'filename': 'example.txt',
                'content': 'Sample content for processing'
            }).encode('utf-8')
        }
    }
    
    response = client.create_task(request={'parent': parent, 'task': task})
    print(f'Task created: {response.name}')
  EOT
}

# Validation and testing outputs
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_queue_status = "gcloud tasks queues describe ${google_cloud_tasks_queue.background_tasks.name} --location=${var.region}"
    check_function_status = "gcloud functions describe ${google_cloudfunctions2_function.task_processor.name} --gen2 --region=${var.region}"
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.task_results.name}/"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.task_processor.name} --gen2 --region=${var.region} --limit=10"
  }
}

# Environment variables for local development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    PROJECT_ID = var.project_id
    REGION = var.region
    QUEUE_NAME = google_cloud_tasks_queue.background_tasks.name
    FUNCTION_NAME = google_cloudfunctions2_function.task_processor.name
    FUNCTION_URL = google_cloudfunctions2_function.task_processor.service_config[0].uri
    STORAGE_BUCKET = google_storage_bucket.task_results.name
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for this deployment (in USD)"
  value = {
    cloud_function_info = "Cloud Functions: $0.0000004/invocation + $0.0000025/GB-second"
    cloud_tasks_info = "Cloud Tasks: $0.40/million operations"
    cloud_storage_info = "Cloud Storage Standard: $0.020/GB-month + $0.0004/1k Class A operations"
    monitoring_info = "Cloud Monitoring: Free for first 150MB/month of logs"
    estimated_monthly_cost = "$1-5 for light usage (assuming < 10K tasks/month)"
  }
}

# Security and access information
output "security_notes" {
  description = "Security considerations and access information"
  value = {
    function_security = var.allow_unauthenticated_function_invocation ? "Function allows unauthenticated access - suitable for Cloud Tasks integration" : "Function requires authentication"
    iam_roles = "Function service account has roles: storage.objectAdmin, logging.logWriter, monitoring.metricWriter"
    bucket_security = "Bucket uses uniform bucket-level access for enhanced security"
    network_security = "Function ingress allows all traffic for Cloud Tasks integration"
  }
}

# Cleanup information
output "cleanup_commands" {
  description = "Commands to clean up resources when no longer needed"
  value = {
    destroy_terraform = "terraform destroy"
    manual_cleanup = [
      "gsutil -m rm -r gs://${google_storage_bucket.task_results.name}",
      "gcloud functions delete ${google_cloudfunctions2_function.task_processor.name} --gen2 --region=${var.region}",
      "gcloud tasks queues delete ${google_cloud_tasks_queue.background_tasks.name} --location=${var.region}",
      "gcloud iam service-accounts delete ${google_service_account.function_sa.email}"
    ]
  }
}