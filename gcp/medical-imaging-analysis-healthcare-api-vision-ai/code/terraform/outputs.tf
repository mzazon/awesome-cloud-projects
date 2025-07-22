# =============================================================================
# TERRAFORM OUTPUTS FOR MEDICAL IMAGING ANALYSIS INFRASTRUCTURE
# =============================================================================

# =============================================================================
# PROJECT AND LOCATION INFORMATION
# =============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
}

# =============================================================================
# HEALTHCARE API RESOURCES
# =============================================================================

output "healthcare_dataset_id" {
  description = "ID of the Healthcare API dataset"
  value       = google_healthcare_dataset.medical_imaging_dataset.id
}

output "healthcare_dataset_name" {
  description = "Name of the Healthcare API dataset"
  value       = google_healthcare_dataset.medical_imaging_dataset.name
}

output "dicom_store_id" {
  description = "ID of the DICOM store"
  value       = google_healthcare_dicom_store.medical_dicom_store.id
}

output "dicom_store_name" {
  description = "Name of the DICOM store"
  value       = google_healthcare_dicom_store.medical_dicom_store.name
}

output "fhir_store_id" {
  description = "ID of the FHIR store"
  value       = google_healthcare_fhir_store.medical_fhir_store.id
}

output "fhir_store_name" {
  description = "Name of the FHIR store"
  value       = google_healthcare_fhir_store.medical_fhir_store.name
}

output "fhir_store_version" {
  description = "FHIR version of the FHIR store"
  value       = google_healthcare_fhir_store.medical_fhir_store.version
}

# =============================================================================
# CLOUD STORAGE RESOURCES
# =============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for medical images"
  value       = google_storage_bucket.medical_imaging_bucket.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.medical_imaging_bucket.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.medical_imaging_bucket.location
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.medical_imaging_bucket.self_link
}

# =============================================================================
# CLOUD FUNCTIONS RESOURCES
# =============================================================================

output "cloud_function_name" {
  description = "Name of the Cloud Function for medical image processing"
  value       = google_cloudfunctions2_function.medical_image_processor.name
}

output "cloud_function_url" {
  description = "URL of the Cloud Function"
  value       = google_cloudfunctions2_function.medical_image_processor.service_config[0].uri
}

output "cloud_function_location" {
  description = "Location of the Cloud Function"
  value       = google_cloudfunctions2_function.medical_image_processor.location
}

output "cloud_function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.medical_image_processor.state
}

# =============================================================================
# PUB/SUB RESOURCES
# =============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for medical image processing"
  value       = google_pubsub_topic.medical_image_processing.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic"
  value       = google_pubsub_topic.medical_image_processing.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.medical_image_processor_sub.name
}

output "pubsub_subscription_id" {
  description = "ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.medical_image_processor_sub.id
}

output "pubsub_dlq_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.medical_image_processing_dlq.name
}

# =============================================================================
# SERVICE ACCOUNT INFORMATION
# =============================================================================

output "service_account_email" {
  description = "Email address of the medical imaging service account"
  value       = google_service_account.medical_imaging_sa.email
}

output "service_account_name" {
  description = "Name of the medical imaging service account"
  value       = google_service_account.medical_imaging_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the medical imaging service account"
  value       = google_service_account.medical_imaging_sa.unique_id
}

# =============================================================================
# MONITORING AND ALERTING INFORMATION
# =============================================================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "log_metrics" {
  description = "Names of the created log-based metrics"
  value = var.enable_monitoring ? {
    success_metric = google_logging_metric.medical_image_processing_success[0].name
    failure_metric = google_logging_metric.medical_image_processing_failure[0].name
  } : {}
}

output "alert_policies" {
  description = "Names of the created alert policies"
  value = var.enable_monitoring ? {
    function_failure_alert = google_monitoring_alert_policy.function_failure_alert[0].display_name
  } : {}
}

output "notification_channels" {
  description = "Notification channels for alerts"
  value = var.enable_monitoring && var.alert_email != "" ? {
    email_channel = google_monitoring_notification_channel.email_alert[0].display_name
  } : {}
}

# =============================================================================
# SECURITY AND ACCESS INFORMATION
# =============================================================================

output "bucket_uniform_access_enabled" {
  description = "Whether uniform bucket-level access is enabled"
  value       = google_storage_bucket.medical_imaging_bucket.uniform_bucket_level_access
}

output "bucket_versioning_enabled" {
  description = "Whether bucket versioning is enabled"
  value       = google_storage_bucket.medical_imaging_bucket.versioning[0].enabled
}

# =============================================================================
# DEPLOYMENT VERIFICATION COMMANDS
# =============================================================================

output "verification_commands" {
  description = "CLI commands to verify the deployment"
  value = {
    check_dataset = "gcloud healthcare datasets describe ${google_healthcare_dataset.medical_imaging_dataset.name} --location=${var.region}"
    check_dicom_store = "gcloud healthcare dicom-stores describe ${google_healthcare_dicom_store.medical_dicom_store.name} --dataset=${google_healthcare_dataset.medical_imaging_dataset.name} --location=${var.region}"
    check_fhir_store = "gcloud healthcare fhir-stores describe ${google_healthcare_fhir_store.medical_fhir_store.name} --dataset=${google_healthcare_dataset.medical_imaging_dataset.name} --location=${var.region}"
    check_function = "gcloud functions describe ${google_cloudfunctions2_function.medical_image_processor.name} --region=${var.region} --gen2"
    check_bucket = "gsutil ls -L gs://${google_storage_bucket.medical_imaging_bucket.name}"
    check_pubsub_topic = "gcloud pubsub topics describe ${google_pubsub_topic.medical_image_processing.name}"
    check_subscription = "gcloud pubsub subscriptions describe ${google_pubsub_subscription.medical_image_processor_sub.name}"
  }
}

# =============================================================================
# TESTING AND VALIDATION INFORMATION
# =============================================================================

output "test_resources" {
  description = "Information about test resources and sample data"
  value = {
    sample_metadata_path = "gs://${google_storage_bucket.medical_imaging_bucket.name}/incoming/sample_study.json"
    incoming_folder = "gs://${google_storage_bucket.medical_imaging_bucket.name}/incoming/"
    processed_folder = "gs://${google_storage_bucket.medical_imaging_bucket.name}/processed/"
    failed_folder = "gs://${google_storage_bucket.medical_imaging_bucket.name}/failed/"
  }
}

# =============================================================================
# COST ESTIMATION AND RESOURCE SUMMARY
# =============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    healthcare_dataset = 1
    dicom_stores = 1
    fhir_stores = 1
    cloud_functions = 1
    storage_buckets = 1
    pubsub_topics = 2  # Main topic + DLQ
    pubsub_subscriptions = 1
    service_accounts = 1
    log_metrics = var.enable_monitoring ? 2 : 0
    alert_policies = var.enable_monitoring ? 1 : 0
    notification_channels = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  }
}

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure (USD)"
  value = {
    note = "Costs vary based on usage. These are estimates for light usage."
    healthcare_api = "$0-50 (depends on data volume)"
    cloud_functions = "$0-20 (first 2M invocations free)"
    cloud_storage = "$0-10 (depends on storage volume)"
    pubsub = "$0-5 (first 10GB free)"
    vision_ai = "$1.50 per 1,000 images (first 1,000 free monthly)"
    monitoring = "$0-5 (depends on metrics volume)"
    total_estimated = "$5-100 depending on usage"
  }
}

# =============================================================================
# NEXT STEPS AND USAGE GUIDANCE
# =============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step_1 = "Verify all resources are created using the verification commands"
    step_2 = "Upload test DICOM images to gs://${google_storage_bucket.medical_imaging_bucket.name}/incoming/"
    step_3 = "Monitor function logs: gcloud functions logs read ${google_cloudfunctions2_function.medical_image_processor.name} --region=${var.region} --gen2"
    step_4 = "Check processing results in the FHIR store and processed folder"
    step_5 = "Set up additional monitoring and alerting as needed"
    step_6 = "Configure authentication and access controls for production use"
  }
}

output "important_notes" {
  description = "Important notes about the deployment"
  value = {
    security = "This deployment creates HIPAA-compliant infrastructure but requires proper BAAs with Google Cloud"
    compliance = "Ensure all healthcare data handling complies with local regulations (HIPAA, GDPR, etc.)"
    monitoring = "Monitor costs closely as Vision AI charges per image processed"
    testing = "Use only test/synthetic data until proper security reviews are completed"
    production = "Additional security hardening required for production workloads"
  }
}