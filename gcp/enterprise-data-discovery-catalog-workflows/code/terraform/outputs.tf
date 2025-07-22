# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# ============================================================================
# SERVICE ACCOUNT OUTPUTS
# ============================================================================

output "service_account_email" {
  description = "Email address of the data discovery service account"
  value       = google_service_account.data_discovery_sa.email
}

output "service_account_name" {
  description = "Full name of the data discovery service account"
  value       = google_service_account.data_discovery_sa.name
}

output "service_account_unique_id" {
  description = "Unique ID of the data discovery service account"
  value       = google_service_account.data_discovery_sa.unique_id
}

# ============================================================================
# DATA CATALOG OUTPUTS
# ============================================================================

output "tag_templates" {
  description = "Information about created Data Catalog tag templates"
  value = {
    for template_name, template in google_data_catalog_tag_template.templates : 
    template_name => {
      id           = template.id
      name         = template.name
      display_name = template.display_name
      region       = template.region
    }
  }
}

output "data_catalog_urls" {
  description = "URLs to access Data Catalog resources in the Google Cloud Console"
  value = {
    catalog_ui = "https://console.cloud.google.com/datacatalog?project=${var.project_id}"
    tag_templates = {
      for template_name, template in google_data_catalog_tag_template.templates :
      template_name => "https://console.cloud.google.com/datacatalog/tag-templates/${template.tag_template_id}?project=${var.project_id}&region=${var.region}"
    }
  }
}

# ============================================================================
# CLOUD FUNCTION OUTPUTS
# ============================================================================

output "cloud_function" {
  description = "Information about the metadata extraction Cloud Function"
  value = {
    name        = google_cloudfunctions2_function.metadata_extractor.name
    location    = google_cloudfunctions2_function.metadata_extractor.location
    url         = google_cloudfunctions2_function.metadata_extractor.service_config[0].uri
    trigger_url = "https://${var.region}-${var.project_id}.cloudfunctions.net/${local.function_name}"
  }
}

output "function_logs_url" {
  description = "URL to view Cloud Function logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${local.function_name}/logs?project=${var.project_id}"
}

# ============================================================================
# CLOUD WORKFLOWS OUTPUTS
# ============================================================================

output "workflow" {
  description = "Information about the data discovery workflow"
  value = {
    name     = google_workflows_workflow.data_discovery.name
    region   = google_workflows_workflow.data_discovery.region
    state    = google_workflows_workflow.data_discovery.state
  }
}

output "workflow_urls" {
  description = "URLs to access workflow resources in the Google Cloud Console"
  value = {
    workflow_ui   = "https://console.cloud.google.com/workflows/workflow/${var.region}/${local.workflow_name}?project=${var.project_id}"
    executions_ui = "https://console.cloud.google.com/workflows/workflow/${var.region}/${local.workflow_name}/executions?project=${var.project_id}"
  }
}

# ============================================================================
# CLOUD SCHEDULER OUTPUTS
# ============================================================================

output "scheduler_jobs" {
  description = "Information about the automated discovery scheduler jobs"
  value = {
    daily = {
      name     = google_cloud_scheduler_job.daily_discovery.name
      schedule = google_cloud_scheduler_job.daily_discovery.schedule
      timezone = google_cloud_scheduler_job.daily_discovery.time_zone
      state    = google_cloud_scheduler_job.daily_discovery.state
    }
    weekly = {
      name     = google_cloud_scheduler_job.weekly_discovery.name
      schedule = google_cloud_scheduler_job.weekly_discovery.schedule
      timezone = google_cloud_scheduler_job.weekly_discovery.time_zone
      state    = google_cloud_scheduler_job.weekly_discovery.state
    }
  }
}

output "scheduler_urls" {
  description = "URLs to access scheduler jobs in the Google Cloud Console"
  value = {
    daily_job  = "https://console.cloud.google.com/cloudscheduler/jobs/edit/${var.region}/${local.scheduler_job_daily}?project=${var.project_id}"
    weekly_job = "https://console.cloud.google.com/cloudscheduler/jobs/edit/${var.region}/${local.scheduler_job_weekly}?project=${var.project_id}"
    all_jobs   = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  }
}

# ============================================================================
# SAMPLE DATA OUTPUTS
# ============================================================================

output "sample_bigquery_datasets" {
  description = "Information about created sample BigQuery datasets"
  value = {
    for dataset_name, dataset in google_bigquery_dataset.sample_datasets :
    dataset_name => {
      id           = dataset.id
      dataset_id   = dataset.dataset_id
      friendly_name = dataset.friendly_name
      location     = dataset.location
      self_link    = dataset.self_link
    }
  }
}

output "sample_storage_buckets" {
  description = "Information about created sample Cloud Storage buckets"
  value = {
    for bucket_name, bucket in google_storage_bucket.sample_buckets :
    bucket_name => {
      name         = bucket.name
      location     = bucket.location
      storage_class = bucket.storage_class
      url          = bucket.url
      self_link    = bucket.self_link
    }
  }
}

output "bigquery_console_urls" {
  description = "URLs to access sample BigQuery datasets in the Google Cloud Console"
  value = {
    for dataset_name, dataset in google_bigquery_dataset.sample_datasets :
    dataset_name => "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${dataset.dataset_id}!3e1"
  }
}

output "storage_console_urls" {
  description = "URLs to access sample Cloud Storage buckets in the Google Cloud Console"
  value = {
    for bucket_name, bucket in google_storage_bucket.sample_buckets :
    bucket_name => "https://console.cloud.google.com/storage/browser/${bucket.name}?project=${var.project_id}"
  }
}

# ============================================================================
# OPERATIONAL OUTPUTS
# ============================================================================

output "manual_execution_commands" {
  description = "Commands to manually execute the data discovery workflow"
  value = {
    gcloud_execute = "gcloud workflows run ${local.workflow_name} --location=${var.region} --data='{\"suffix\": \"${local.resource_suffix}\"}'"
    list_executions = "gcloud workflows executions list --workflow=${local.workflow_name} --location=${var.region}"
    get_latest_execution = "gcloud workflows executions describe $(gcloud workflows executions list --workflow=${local.workflow_name} --location=${var.region} --limit=1 --format='value(name.basename())') --workflow=${local.workflow_name} --location=${var.region}"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring and observability"
  value = {
    function_monitoring = "https://console.cloud.google.com/monitoring/dashboards/custom/cloudfunctions?project=${var.project_id}"
    workflow_monitoring = "https://console.cloud.google.com/monitoring/dashboards/custom/workflows?project=${var.project_id}"
    logs_explorer      = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    error_reporting    = "https://console.cloud.google.com/errors?project=${var.project_id}"
  }
}

output "validation_commands" {
  description = "Commands to validate the deployed infrastructure and test functionality"
  value = {
    test_function = "curl -X POST https://${var.region}-${var.project_id}.cloudfunctions.net/${local.function_name} -H 'Content-Type: application/json' -d '{\"project_id\": \"${var.project_id}\", \"location\": \"${var.region}\"}'"
    list_tag_templates = "gcloud data-catalog tag-templates list --location=${var.region}"
    search_catalog = "gcloud data-catalog entries search --location=${var.region} --query='type=table'"
    check_scheduler = "gcloud scheduler jobs list --location=${var.region}"
  }
}

# ============================================================================
# CLEANUP COMMANDS
# ============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    pause_schedulers = "gcloud scheduler jobs pause ${local.scheduler_job_daily} --location=${var.region} && gcloud scheduler jobs pause ${local.scheduler_job_weekly} --location=${var.region}"
    delete_sample_data = "bq rm -r -f ${var.project_id}:customer_analytics_${local.resource_suffix} && bq rm -r -f ${var.project_id}:hr_internal_${local.resource_suffix}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ============================================================================

output "security_information" {
  description = "Security and compliance information for the deployed infrastructure"
  value = {
    service_account_roles = var.service_account_roles
    encryption_at_rest   = "All data is encrypted at rest using Google-managed encryption keys"
    network_access       = "Cloud Function allows unauthenticated access for testing - restrict in production"
    data_classification  = "Tag templates created for data sensitivity classification"
    audit_logging        = "All operations are logged via Google Cloud Audit Logs"
  }
}