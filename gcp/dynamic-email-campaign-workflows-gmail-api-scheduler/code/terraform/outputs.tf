# Project and Region Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where resources are deployed"
  value       = var.zone
}

# Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for campaign data"
  value       = google_storage_bucket.campaign_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.campaign_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.campaign_data.self_link
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account for email automation"
  value       = google_service_account.email_automation.email
}

output "service_account_name" {
  description = "Name of the service account for email automation"
  value       = google_service_account.email_automation.name
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.email_automation.unique_id
}

# Cloud Functions Information
output "campaign_generator_function_name" {
  description = "Name of the Campaign Generator Cloud Function"
  value       = google_cloudfunctions_function.campaign_generator.name
}

output "campaign_generator_function_url" {
  description = "HTTP trigger URL for the Campaign Generator function"
  value       = google_cloudfunctions_function.campaign_generator.https_trigger_url
}

output "email_sender_function_name" {
  description = "Name of the Email Sender Cloud Function"
  value       = google_cloudfunctions_function.email_sender.name
}

output "email_sender_function_url" {
  description = "HTTP trigger URL for the Email Sender function"
  value       = google_cloudfunctions_function.email_sender.https_trigger_url
}

output "analytics_function_name" {
  description = "Name of the Analytics Cloud Function"
  value       = google_cloudfunctions_function.analytics.name
}

output "analytics_function_url" {
  description = "HTTP trigger URL for the Analytics function"
  value       = google_cloudfunctions_function.analytics.https_trigger_url
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for email campaigns"
  value       = google_bigquery_dataset.email_campaigns.dataset_id
}

output "bigquery_dataset_self_link" {
  description = "Self-link of the BigQuery dataset"
  value       = google_bigquery_dataset.email_campaigns.self_link
}

output "user_behavior_table_id" {
  description = "ID of the user behavior tracking table"
  value       = google_bigquery_table.user_behavior.table_id
}

output "campaign_metrics_table_id" {
  description = "ID of the campaign metrics table"
  value       = google_bigquery_table.campaign_metrics.table_id
}

# Cloud Scheduler Jobs
output "daily_campaign_scheduler_name" {
  description = "Name of the daily campaign scheduler job"
  value       = google_cloud_scheduler_job.daily_campaign_generator.name
}

output "weekly_newsletter_scheduler_name" {
  description = "Name of the weekly newsletter scheduler job"
  value       = google_cloud_scheduler_job.weekly_newsletter.name
}

output "promotional_campaigns_scheduler_name" {
  description = "Name of the promotional campaigns scheduler job"
  value       = google_cloud_scheduler_job.promotional_campaigns.name
}

# Monitoring Resources
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = var.monitoring_enabled ? google_monitoring_dashboard.email_campaigns[0].id : null
}

output "alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = var.monitoring_enabled ? google_monitoring_alert_policy.function_error_rate[0].name : null
}

# Configuration Values
output "email_templates" {
  description = "Map of email templates and their configurations"
  value = {
    for template_name, template_config in var.email_templates : template_name => {
      subject     = template_config.subject
      description = template_config.description
      storage_path = "templates/${template_name}.html"
    }
  }
}

output "scheduler_configurations" {
  description = "Configuration of all scheduler jobs"
  value = {
    daily_campaign = {
      name        = google_cloud_scheduler_job.daily_campaign_generator.name
      schedule    = var.daily_campaign_schedule
      time_zone   = var.scheduler_time_zone
      description = "Daily email campaign generation"
    }
    weekly_newsletter = {
      name        = google_cloud_scheduler_job.weekly_newsletter.name
      schedule    = var.weekly_newsletter_schedule
      time_zone   = var.scheduler_time_zone
      description = "Weekly newsletter campaign"
    }
    promotional_campaigns = {
      name        = google_cloud_scheduler_job.promotional_campaigns.name
      schedule    = var.promotional_campaign_schedule
      time_zone   = var.scheduler_time_zone
      description = "Promotional email campaigns"
    }
  }
}

# Resource Naming
output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# API Endpoints for Testing
output "api_endpoints" {
  description = "API endpoints for testing the email campaign system"
  value = {
    campaign_generator = {
      url    = google_cloudfunctions_function.campaign_generator.https_trigger_url
      method = "POST"
      description = "Generate personalized email campaigns"
    }
    email_sender = {
      url    = google_cloudfunctions_function.email_sender.https_trigger_url
      method = "POST"
      description = "Send personalized emails via Gmail API"
    }
    analytics = {
      url    = google_cloudfunctions_function.analytics.https_trigger_url
      method = "POST"
      description = "Analyze campaign performance and generate insights"
    }
  }
}

# Security Information
output "gmail_api_scopes" {
  description = "OAuth scopes configured for Gmail API access"
  value       = var.gmail_scopes
}

output "iam_roles_assigned" {
  description = "List of IAM roles assigned to the service account"
  value       = var.service_account_roles
}

# Cost Management
output "budget_amount" {
  description = "Monthly budget amount configured for the system"
  value       = var.budget_amount
}

output "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  value       = var.budget_alert_thresholds
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    storage_bucket      = google_storage_bucket.campaign_data.name
    service_account     = google_service_account.email_automation.email
    cloud_functions     = {
      campaign_generator = google_cloudfunctions_function.campaign_generator.name
      email_sender       = google_cloudfunctions_function.email_sender.name
      analytics         = google_cloudfunctions_function.analytics.name
    }
    bigquery_dataset    = google_bigquery_dataset.email_campaigns.dataset_id
    scheduler_jobs      = {
      daily_campaign      = google_cloud_scheduler_job.daily_campaign_generator.name
      weekly_newsletter   = google_cloud_scheduler_job.weekly_newsletter.name
      promotional_campaigns = google_cloud_scheduler_job.promotional_campaigns.name
    }
    monitoring_enabled  = var.monitoring_enabled
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    step_1 = "Configure OAuth 2.0 credentials for Gmail API in Google Cloud Console"
    step_2 = "Update service account key in Cloud Storage with Gmail API permissions"
    step_3 = "Populate BigQuery tables with sample user behavior data"
    step_4 = "Test Cloud Functions using the provided API endpoints"
    step_5 = "Monitor scheduler jobs and adjust schedules as needed"
    step_6 = "Set up email domain authentication (SPF, DKIM, DMARC)"
  }
}

# Documentation Links
output "documentation_links" {
  description = "Useful documentation links for the email campaign system"
  value = {
    gmail_api_docs        = "https://developers.google.com/gmail/api"
    cloud_scheduler_docs  = "https://cloud.google.com/scheduler/docs"
    cloud_functions_docs  = "https://cloud.google.com/functions/docs"
    bigquery_docs        = "https://cloud.google.com/bigquery/docs"
    cloud_storage_docs   = "https://cloud.google.com/storage/docs"
    monitoring_docs      = "https://cloud.google.com/monitoring/docs"
  }
}