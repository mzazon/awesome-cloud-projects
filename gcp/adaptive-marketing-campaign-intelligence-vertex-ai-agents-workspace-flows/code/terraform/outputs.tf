# =====================================
# Outputs for Adaptive Marketing Campaign Intelligence
# with Vertex AI Agents and Google Workspace Flows
# =====================================

# =====================================
# Project and Infrastructure Information
# =====================================

output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Primary region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# =====================================
# BigQuery Data Warehouse Outputs
# =====================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for marketing intelligence data"
  value       = google_bigquery_dataset.marketing_data.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.marketing_data.location
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.marketing_data.dataset_id}!3s"
}

output "campaign_performance_table" {
  description = "Full table ID for campaign performance data"
  value       = "${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.campaign_performance.table_id}"
}

output "customer_interactions_table" {
  description = "Full table ID for customer interaction data"
  value       = "${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.customer_interactions.table_id}"
}

output "ai_insights_table" {
  description = "Full table ID for AI-generated insights"
  value       = "${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.ai_insights.table_id}"
}

output "campaign_dashboard_view" {
  description = "Full view ID for the campaign dashboard"
  value       = "${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.campaign_dashboard_view.table_id}"
}

output "customer_ltv_model" {
  description = "Full model ID for customer lifetime value prediction"
  value       = "${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.customer_ltv_model.table_id}"
}

# =====================================
# Cloud Storage Outputs
# =====================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for marketing intelligence data"
  value       = google_storage_bucket.marketing_intelligence_bucket.name
}

output "storage_bucket_url" {
  description = "URL to access the Cloud Storage bucket"
  value       = google_storage_bucket.marketing_intelligence_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self-link for the Cloud Storage bucket"
  value       = google_storage_bucket.marketing_intelligence_bucket.self_link
}

output "sample_data_paths" {
  description = "Paths to sample data files in the storage bucket"
  value = {
    campaign_performance = "gs://${google_storage_bucket.marketing_intelligence_bucket.name}/${google_storage_bucket_object.sample_campaign_data.name}"
    customer_interactions = "gs://${google_storage_bucket.marketing_intelligence_bucket.name}/${google_storage_bucket_object.sample_customer_data.name}"
  }
}

# =====================================
# Service Account Outputs
# =====================================

output "vertex_ai_service_account" {
  description = "Service account for Vertex AI operations"
  value = {
    email        = google_service_account.vertex_ai_service_account.email
    account_id   = google_service_account.vertex_ai_service_account.account_id
    display_name = google_service_account.vertex_ai_service_account.display_name
    unique_id    = google_service_account.vertex_ai_service_account.unique_id
  }
}

output "workspace_flows_service_account" {
  description = "Service account for Google Workspace Flows integration"
  value = {
    email        = google_service_account.workspace_flows_service_account.email
    account_id   = google_service_account.workspace_flows_service_account.account_id
    display_name = google_service_account.workspace_flows_service_account.display_name
    unique_id    = google_service_account.workspace_flows_service_account.unique_id
  }
}

# =====================================
# Vertex AI Workbench Outputs
# =====================================

output "workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance"
  value       = google_workbench_instance.marketing_ai_workbench.name
}

output "workbench_instance_url" {
  description = "URL to access the Vertex AI Workbench instance"
  value       = "https://console.cloud.google.com/vertex-ai/workbench/list/instances?project=${var.project_id}"
}

output "workbench_proxy_uri" {
  description = "Proxy URI for accessing the Workbench instance"
  value       = google_workbench_instance.marketing_ai_workbench.proxy_uri
  sensitive   = true
}

# =====================================
# IAM and Security Outputs
# =====================================

output "custom_iam_role" {
  description = "Custom IAM role created for marketing automation"
  value = {
    name  = google_project_iam_custom_role.marketing_automation_role.name
    title = google_project_iam_custom_role.marketing_automation_role.title
    id    = google_project_iam_custom_role.marketing_automation_role.role_id
  }
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = [for api in google_project_service.required_apis : api.service]
}

# =====================================
# Monitoring and Alerting Outputs
# =====================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "notification_channels" {
  description = "Notification channels for monitoring alerts"
  value = var.enable_monitoring && var.alert_email != "" ? {
    email_alerts = {
      name         = google_monitoring_notification_channel.email_alerts[0].name
      display_name = google_monitoring_notification_channel.email_alerts[0].display_name
      type         = google_monitoring_notification_channel.email_alerts[0].type
    }
  } : {}
}

output "alert_policies" {
  description = "Created alert policies for system monitoring"
  value = var.enable_monitoring ? {
    bigquery_job_failures = {
      name         = google_monitoring_alert_policy.bigquery_job_failures[0].name
      display_name = google_monitoring_alert_policy.bigquery_job_failures[0].display_name
    }
    storage_access_anomalies = {
      name         = google_monitoring_alert_policy.storage_access_anomalies[0].name
      display_name = google_monitoring_alert_policy.storage_access_anomalies[0].display_name
    }
  } : {}
}

# =====================================
# Data Loading and Integration Outputs
# =====================================

output "data_loading_commands" {
  description = "Commands for loading data into BigQuery tables"
  value = {
    campaign_performance = "bq load --source_format=CSV --skip_leading_rows=1 ${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.campaign_performance.table_id} gs://${google_storage_bucket.marketing_intelligence_bucket.name}/data/campaign_performance.csv"
    customer_interactions = "bq load --source_format=CSV --skip_leading_rows=1 ${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.customer_interactions.table_id} gs://${google_storage_bucket.marketing_intelligence_bucket.name}/data/customer_interactions.csv"
  }
}

output "sample_queries" {
  description = "Sample BigQuery queries for testing the system"
  value = {
    campaign_overview = "SELECT campaign_name, channel, SUM(impressions) as total_impressions, SUM(clicks) as total_clicks, AVG(ctr) as avg_ctr FROM `${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.campaign_performance.table_id}` GROUP BY campaign_name, channel ORDER BY total_impressions DESC"
    customer_engagement = "SELECT demographic_segment, AVG(engagement_score) as avg_engagement, COUNT(*) as interaction_count FROM `${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.customer_interactions.table_id}` GROUP BY demographic_segment ORDER BY avg_engagement DESC"
    ai_insights_summary = "SELECT insight_type, priority_level, COUNT(*) as insight_count, AVG(confidence_score) as avg_confidence FROM `${var.project_id}.${google_bigquery_dataset.marketing_data.dataset_id}.${google_bigquery_table.ai_insights.table_id}` GROUP BY insight_type, priority_level ORDER BY insight_count DESC"
  }
}

# =====================================
# Workspace Integration Outputs
# =====================================

output "workspace_api_configuration" {
  description = "Configuration details for Google Workspace API integration"
  value = {
    gmail_api_enabled    = var.gmail_api_enabled
    sheets_api_enabled   = var.sheets_api_enabled
    docs_api_enabled     = var.docs_api_enabled
    calendar_api_enabled = var.calendar_api_enabled
    workspace_domain     = var.workspace_domain
    flows_enabled        = var.enable_workspace_flows
  }
}

output "service_account_keys_note" {
  description = "Important note about service account key management"
  value       = "Service account keys are not created by this Terraform configuration for security reasons. Create keys manually in the Google Cloud Console if needed for external applications, or use Workload Identity Federation for secure authentication."
}

# =====================================
# Cost Optimization Outputs
# =====================================

output "cost_optimization_features" {
  description = "Enabled cost optimization features"
  value = {
    storage_lifecycle_enabled = var.enable_cost_optimization
    table_expiration_days     = var.table_expiration_days
    bigquery_slot_commitment  = var.bigquery_slot_commitment
    archive_after_days        = var.storage_archive_after_days
  }
}

# =====================================
# Next Steps and URLs
# =====================================

output "next_steps" {
  description = "Next steps for setting up the marketing intelligence system"
  value = [
    "1. Access the Vertex AI Workbench instance to start developing AI models",
    "2. Upload your marketing data to the Cloud Storage bucket",
    "3. Load data into BigQuery tables using the provided commands",
    "4. Configure Google Workspace API credentials for automation",
    "5. Set up Vertex AI Agents for intelligent campaign analysis",
    "6. Configure Google Workspace Flows for automated workflows",
    "7. Test the system with sample data and queries"
  ]
}

output "useful_links" {
  description = "Useful links for managing and monitoring the system"
  value = {
    bigquery_console     = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    vertex_ai_console    = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    storage_console      = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    monitoring_console   = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    iam_console         = "https://console.cloud.google.com/iam-admin?project=${var.project_id}"
    workspace_admin     = "https://admin.google.com/"
    vertex_ai_workbench = "https://console.cloud.google.com/vertex-ai/workbench?project=${var.project_id}"
  }
}

# =====================================
# Security and Compliance Outputs
# =====================================

output "security_configuration" {
  description = "Security and compliance configuration summary"
  value = {
    uniform_bucket_level_access = google_storage_bucket.marketing_intelligence_bucket.uniform_bucket_level_access
    public_access_prevention    = google_storage_bucket.marketing_intelligence_bucket.public_access_prevention
    workbench_public_ip_disabled = var.disable_workbench_public_ip
    kms_encryption_enabled      = var.kms_key_name != null
    audit_logging_enabled       = var.enable_audit_logging
    dlp_enabled                = var.enable_data_loss_prevention
  }
}

output "resource_labels" {
  description = "Labels applied to all resources for organization and billing"
  value       = local.common_labels
}

# =====================================
# Version and Metadata Outputs
# =====================================

output "terraform_version_info" {
  description = "Terraform version information for this deployment"
  value = {
    terraform_version = "~> 1.5"
    google_provider_version = "~> 6.33"
    deployment_timestamp = timestamp()
  }
}