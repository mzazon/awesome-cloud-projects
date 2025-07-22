# Outputs for Visual Document Processing with Cloud Filestore and Vision AI Solution
# This file defines all output values that provide important information about deployed resources

# ============================================================================
# PROJECT AND REGION INFORMATION
# ============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for deployment"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone used for zonal resources"
  value       = var.zone
}

output "deployment_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# FILESTORE INFORMATION
# ============================================================================

output "filestore_instance_name" {
  description = "Name of the Cloud Filestore instance"
  value       = google_filestore_instance.documents.name
}

output "filestore_ip_address" {
  description = "IP address of the Cloud Filestore instance for NFS mounting"
  value       = google_filestore_instance.documents.networks[0].ip_addresses[0]
}

output "filestore_file_share_name" {
  description = "Name of the file share within the Filestore instance"
  value       = var.filestore_file_share_name
}

output "filestore_capacity_gb" {
  description = "Capacity of the Filestore instance in GB"
  value       = google_filestore_instance.documents.file_shares[0].capacity_gb
}

output "filestore_tier" {
  description = "Service tier of the Filestore instance"
  value       = google_filestore_instance.documents.tier
}

output "filestore_mount_command" {
  description = "Command to mount the Filestore on a client machine"
  value       = "sudo mount -t nfs ${google_filestore_instance.documents.networks[0].ip_addresses[0]}:/${var.filestore_file_share_name} /mnt/filestore"
}

# ============================================================================
# STORAGE BUCKET INFORMATION
# ============================================================================

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the function source bucket"
  value       = google_storage_bucket.function_source.url
}

output "results_bucket_name" {
  description = "Name of the Cloud Storage bucket for processed document results"
  value       = google_storage_bucket.results.name
}

output "results_bucket_url" {
  description = "URL of the results bucket"
  value       = google_storage_bucket.results.url
}

output "results_bucket_console_url" {
  description = "Google Cloud Console URL for the results bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.results.name}?project=${var.project_id}"
}

# ============================================================================
# PUB/SUB INFORMATION
# ============================================================================

output "document_processing_topic_name" {
  description = "Name of the Pub/Sub topic for document processing queue"
  value       = google_pubsub_topic.document_processing.name
}

output "document_processing_topic_id" {
  description = "Full ID of the document processing topic"
  value       = google_pubsub_topic.document_processing.id
}

output "processing_results_topic_name" {
  description = "Name of the Pub/Sub topic for processing results"
  value       = google_pubsub_topic.processing_results.name
}

output "processing_results_topic_id" {
  description = "Full ID of the processing results topic"
  value       = google_pubsub_topic.processing_results.id
}

output "document_processing_subscription_name" {
  description = "Name of the subscription for document processing"
  value       = google_pubsub_subscription.document_processing.name
}

output "processing_results_subscription_name" {
  description = "Name of the subscription for processing results"
  value       = google_pubsub_subscription.processing_results.name
}

# ============================================================================
# CLOUD FUNCTIONS INFORMATION
# ============================================================================

output "file_monitor_function_name" {
  description = "Name of the file monitor Cloud Function"
  value       = var.create_sample_functions ? google_cloudfunctions2_function.file_monitor[0].name : "Not created"
}

output "file_monitor_function_url" {
  description = "URL of the file monitor Cloud Function"
  value       = var.create_sample_functions ? google_cloudfunctions2_function.file_monitor[0].service_config[0].uri : "Not created"
}

output "vision_processor_function_name" {
  description = "Name of the Vision AI processor Cloud Function"
  value       = var.create_sample_functions ? google_cloudfunctions2_function.vision_processor[0].name : "Not created"
}

output "vision_processor_function_url" {
  description = "URL of the Vision AI processor Cloud Function"
  value       = var.create_sample_functions ? google_cloudfunctions2_function.vision_processor[0].service_config[0].uri : "Not created"
}

output "functions_console_url" {
  description = "Google Cloud Console URL for Cloud Functions"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

# ============================================================================
# COMPUTE ENGINE CLIENT INFORMATION
# ============================================================================

output "client_instance_name" {
  description = "Name of the Filestore client Compute Engine instance"
  value       = var.create_client_instance ? google_compute_instance.filestore_client[0].name : "Not created"
}

output "client_instance_internal_ip" {
  description = "Internal IP address of the client instance"
  value       = var.create_client_instance ? google_compute_instance.filestore_client[0].network_interface[0].network_ip : "Not created"
}

output "client_instance_external_ip" {
  description = "External IP address of the client instance"
  value       = var.create_client_instance ? google_compute_instance.filestore_client[0].network_interface[0].access_config[0].nat_ip : "Not created"
}

output "client_ssh_command" {
  description = "SSH command to connect to the client instance"
  value       = var.create_client_instance ? "gcloud compute ssh ${google_compute_instance.filestore_client[0].name} --zone=${var.zone} --project=${var.project_id}" : "Not created"
}

output "client_instance_console_url" {
  description = "Google Cloud Console URL for the client instance"
  value       = var.create_client_instance ? "https://console.cloud.google.com/compute/instancesDetail/zones/${var.zone}/instances/${google_compute_instance.filestore_client[0].name}?project=${var.project_id}" : "Not created"
}

# ============================================================================
# SERVICE ACCOUNT INFORMATION
# ============================================================================

output "service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.function_sa.unique_id
}

# ============================================================================
# TESTING AND VALIDATION COMMANDS
# ============================================================================

output "test_document_upload_command" {
  description = "Command to test document upload to Pub/Sub (run from client instance or Cloud Shell)"
  value = "gcloud pubsub topics publish ${google_pubsub_topic.document_processing.name} --message='{\"filename\":\"test_document.pdf\",\"filepath\":\"/mnt/filestore/${var.filestore_file_share_name}/test_document.pdf\",\"timestamp\":\"$(date -Iseconds)\"}' --project=${var.project_id}"
}

output "view_function_logs_command" {
  description = "Command to view Cloud Function logs"
  value = var.create_sample_functions ? "gcloud functions logs read ${google_cloudfunctions2_function.vision_processor[0].name} --region=${var.region} --project=${var.project_id}" : "Functions not created"
}

output "list_processed_results_command" {
  description = "Command to list processed document results"
  value = "gsutil ls -r gs://${google_storage_bucket.results.name}/processed/"
}

output "mount_filestore_commands" {
  description = "Commands to mount Filestore on a Linux client"
  value = [
    "sudo apt-get update && sudo apt-get install -y nfs-common",
    "sudo mkdir -p /mnt/filestore",
    "sudo mount -t nfs ${google_filestore_instance.documents.networks[0].ip_addresses[0]}:/${var.filestore_file_share_name} /mnt/filestore",
    "sudo mkdir -p /mnt/filestore/{invoices,receipts,contracts}",
    "sudo chmod 755 /mnt/filestore /mnt/filestore/*"
  ]
}

# ============================================================================
# MONITORING AND TROUBLESHOOTING
# ============================================================================

output "pubsub_console_url" {
  description = "Google Cloud Console URL for Pub/Sub topics and subscriptions"
  value = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

output "filestore_console_url" {
  description = "Google Cloud Console URL for Filestore instances"
  value = "https://console.cloud.google.com/filestore/instances?project=${var.project_id}"
}

output "vision_api_console_url" {
  description = "Google Cloud Console URL for Vision API"
  value = "https://console.cloud.google.com/apis/api/vision.googleapis.com/overview?project=${var.project_id}"
}

output "monitoring_dashboard_url" {
  description = "Google Cloud Console URL for monitoring dashboards"
  value = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "logging_console_url" {
  description = "Google Cloud Console URL for viewing logs"
  value = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
}

# ============================================================================
# COST TRACKING INFORMATION
# ============================================================================

output "billing_dashboard_url" {
  description = "Google Cloud Console URL for billing and cost tracking"
  value = "https://console.cloud.google.com/billing?project=${var.project_id}"
}

output "estimated_monthly_cost_components" {
  description = "Breakdown of estimated monthly costs for major components"
  value = {
    filestore_standard_1tb = "~$200-300 USD/month (1TB Standard tier)"
    cloud_functions        = "~$5-20 USD/month (based on usage)"
    cloud_storage         = "~$10-50 USD/month (based on data volume)"
    pubsub               = "~$5-15 USD/month (based on message volume)"
    compute_instance     = "~$15-30 USD/month (e2-medium, if enabled)"
    vision_api           = "~$1.50 per 1000 requests"
    total_estimated      = "~$235-415 USD/month (excluding Vision API usage)"
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE
# ============================================================================

output "iam_roles_applied" {
  description = "IAM roles applied to the service account"
  value = [
    "roles/storage.objectAdmin",
    "roles/pubsub.editor", 
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor"
  ]
}

output "security_considerations" {
  description = "Important security considerations for the deployment"
  value = {
    filestore_access       = "NFS exports limited to private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)"
    function_ingress      = "Cloud Functions configured with ALLOW_INTERNAL_ONLY ingress"
    storage_access        = "Uniform bucket-level access enabled on all buckets"
    service_account       = "Dedicated service account with minimal required permissions"
    client_security       = "Shielded VM features enabled (Secure Boot, vTPM, Integrity Monitoring)"
  }
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    filestore_instance     = "Shared NFS storage for document uploads and processing"
    cloud_functions        = "Serverless document processing with Vision AI integration"
    pubsub_topics         = "Event-driven messaging for scalable document processing pipeline"
    storage_buckets       = "Function source code and processed results storage"
    compute_instance      = "Optional client for demonstration and testing"
    iam_service_account   = "Dedicated service account with least-privilege access"
    firewall_rules        = "Network security for client access and internal communication"
    monitoring_logging    = "Observability and error tracking configuration"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Connect to the client instance using: ${var.create_client_instance ? "gcloud compute ssh ${google_compute_instance.filestore_client[0].name} --zone=${var.zone} --project=${var.project_id}" : "Create a compute instance"}",
    "2. Verify Filestore mount: ls -la /mnt/filestore",
    "3. Upload test documents to /mnt/filestore/${var.filestore_file_share_name}/",
    "4. Test the processing pipeline with: ${var.create_sample_functions ? "gcloud pubsub topics publish ${google_pubsub_topic.document_processing.name} --message='{\"filename\":\"test.pdf\",\"filepath\":\"/mnt/filestore/${var.filestore_file_share_name}/test.pdf\"}' --project=${var.project_id}" : "Deploy sample functions"}",
    "5. Monitor processing results in: gs://${google_storage_bucket.results.name}/processed/",
    "6. View function logs: ${var.create_sample_functions ? "gcloud functions logs read ${google_cloudfunctions2_function.vision_processor[0].name} --region=${var.region} --project=${var.project_id}" : "Deploy functions first"}",
    "7. Set up monitoring dashboards: https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}",
    "8. Review billing and usage: https://console.cloud.google.com/billing?project=${var.project_id}"
  ]
}