# Outputs for Real-Time Analytics Dashboards with Datastream and Looker Studio
# These outputs provide important information about the deployed infrastructure

# Project and Location Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for the deployment"
  value       = var.environment
}

# BigQuery Dataset Information
output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for analytics"
  value       = google_bigquery_dataset.analytics_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.location
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&page=dataset"
}

output "bigquery_dataset_self_link" {
  description = "The self link of the BigQuery dataset"
  value       = google_bigquery_dataset.analytics_dataset.self_link
}

# Datastream Information
output "datastream_id" {
  description = "The ID of the Datastream stream"
  value       = google_datastream_stream.analytics_stream.stream_id
}

output "datastream_name" {
  description = "The full resource name of the Datastream stream"
  value       = google_datastream_stream.analytics_stream.name
}

output "datastream_state" {
  description = "The current state of the Datastream stream"
  value       = google_datastream_stream.analytics_stream.state
}

output "datastream_console_url" {
  description = "URL to access the Datastream in the Google Cloud Console"
  value       = "https://console.cloud.google.com/datastream/streams/locations/${var.region}/instances/${google_datastream_stream.analytics_stream.stream_id}?project=${var.project_id}"
}

# Connection Profile Information
output "source_connection_profile_id" {
  description = "The ID of the source database connection profile"
  value       = google_datastream_connection_profile.source_connection.connection_profile_id
}

output "source_connection_profile_name" {
  description = "The full resource name of the source connection profile"
  value       = google_datastream_connection_profile.source_connection.name
}

output "bigquery_connection_profile_id" {
  description = "The ID of the BigQuery destination connection profile"
  value       = google_datastream_connection_profile.bigquery_connection.connection_profile_id
}

output "bigquery_connection_profile_name" {
  description = "The full resource name of the BigQuery connection profile"
  value       = google_datastream_connection_profile.bigquery_connection.name
}

# BigQuery Views Information
output "bigquery_views" {
  description = "Information about created BigQuery views for analytics"
  value = {
    sales_performance = {
      table_id   = google_bigquery_table.sales_performance_view.table_id
      self_link  = google_bigquery_table.sales_performance_view.self_link
      query_url  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&t=${google_bigquery_table.sales_performance_view.table_id}&page=table"
    }
    daily_sales_summary = {
      table_id   = google_bigquery_table.daily_sales_summary_view.table_id
      self_link  = google_bigquery_table.daily_sales_summary_view.self_link
      query_url  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&t=${google_bigquery_table.daily_sales_summary_view.table_id}&page=table"
    }
    customer_analytics = {
      table_id   = google_bigquery_table.customer_analytics_view.table_id
      self_link  = google_bigquery_table.customer_analytics_view.self_link
      query_url  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&t=${google_bigquery_table.customer_analytics_view.table_id}&page=table"
    }
    product_performance = {
      table_id   = google_bigquery_table.product_performance_view.table_id
      self_link  = google_bigquery_table.product_performance_view.self_link
      query_url  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&t=${google_bigquery_table.product_performance_view.table_id}&page=table"
    }
  }
}

# Looker Studio Connection Information
output "looker_studio_data_source_info" {
  description = "Information needed to connect Looker Studio to BigQuery"
  value = {
    project_id   = var.project_id
    dataset_name = google_bigquery_dataset.analytics_dataset.dataset_id
    tables = [
      google_bigquery_table.sales_performance_view.table_id,
      google_bigquery_table.daily_sales_summary_view.table_id,
      google_bigquery_table.customer_analytics_view.table_id,
      google_bigquery_table.product_performance_view.table_id
    ]
    looker_studio_url = "https://lookerstudio.google.com/reporting/create?c.mode=edit&ds.connector=bigQuery&ds.projectId=${var.project_id}&ds.datasetId=${google_bigquery_dataset.analytics_dataset.dataset_id}"
  }
}

# Service Account Information
output "datastream_service_account" {
  description = "The Datastream service account email"
  value       = "service-${data.google_project.current.number}@gcp-sa-datastream.iam.gserviceaccount.com"
}

# Monitoring and Management URLs
output "console_urls" {
  description = "Useful Google Cloud Console URLs for managing the deployment"
  value = {
    datastream_streams     = "https://console.cloud.google.com/datastream/streams?project=${var.project_id}"
    datastream_profiles    = "https://console.cloud.google.com/datastream/connection-profiles?project=${var.project_id}"
    bigquery_dataset      = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.analytics_dataset.dataset_id}&page=dataset"
    bigquery_console      = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    looker_studio         = "https://lookerstudio.google.com/"
    cloud_logging         = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    cloud_monitoring      = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    iam_roles            = "https://console.cloud.google.com/iam-admin/iam?project=${var.project_id}"
  }
}

# Sample Queries for Testing
output "sample_queries" {
  description = "Sample SQL queries to test the analytics views"
  value = {
    test_data_replication = "SELECT COUNT(*) as total_records, MAX(_metadata_timestamp) as latest_update FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.sales_orders`"
    daily_sales = "SELECT * FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.daily_sales_summary` ORDER BY sales_date DESC LIMIT 30"
    top_customers = "SELECT customer_name, total_spent FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.customer_analytics` ORDER BY total_spent DESC LIMIT 10"
    top_products = "SELECT product_name, total_revenue FROM `${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}.product_performance` ORDER BY total_revenue DESC LIMIT 10"
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    source_database_type = var.source_db_type
    source_hostname     = var.source_db_hostname
    source_port         = var.source_db_port
    data_freshness_seconds = var.data_freshness_seconds
    max_concurrent_cdc_tasks = var.max_concurrent_cdc_tasks
    max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks
    bi_engine_enabled   = var.enable_bi_engine
    looker_studio_users = length(var.looker_studio_users)
  }
}

# BI Engine Information (if enabled)
output "bi_engine_reservation" {
  description = "BI Engine reservation information for enhanced performance"
  value = var.enable_bi_engine ? {
    size_mb = google_bigquery_bi_reservation.analytics_bi_engine[0].size
    location = google_bigquery_bi_reservation.analytics_bi_engine[0].location
    preferred_tables = google_bigquery_bi_reservation.analytics_bi_engine[0].preferred_tables
  } : null
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for estimating costs of the deployed resources"
  value = {
    datastream_note = "Datastream costs depend on data volume and frequency of changes. Pricing is per GB of data processed."
    bigquery_note = "BigQuery costs include storage (per GB per month) and query processing (per TB of data processed)."
    bi_engine_note = var.enable_bi_engine ? "BI Engine costs $0.048 per slot per hour for the reserved capacity." : "BI Engine not enabled."
    cost_calculator_url = "https://cloud.google.com/products/calculator"
  }
}

# Next Steps and Instructions
output "next_steps" {
  description = "Instructions for completing the setup"
  value = {
    "1_verify_datastream" = "Check Datastream status: gcloud datastream streams describe ${google_datastream_stream.analytics_stream.stream_id} --location=${var.region}"
    "2_test_replication" = "Test data replication using the sample queries provided in the 'sample_queries' output"
    "3_create_looker_dashboard" = "Open Looker Studio at https://lookerstudio.google.com/ and create a new report using the BigQuery data source"
    "4_configure_monitoring" = "Set up monitoring and alerting in Google Cloud Console for your analytics pipeline"
    "5_optimize_performance" = "Consider enabling BI Engine if dashboard performance needs improvement"
  }
}

# Security and Compliance Information
output "security_information" {
  description = "Security configuration and compliance information"
  value = {
    encryption_at_rest = "All data is encrypted at rest using Google Cloud's default encryption"
    encryption_in_transit = "All data is encrypted in transit using TLS"
    access_control = "Access is controlled through IAM roles and BigQuery dataset permissions"
    audit_logging = "Cloud Audit Logs are enabled for all API calls and data access"
    data_residency = "Data is stored in the ${var.region} region"
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting steps and resources"
  value = {
    datastream_logs = "View Datastream logs: gcloud logging read 'resource.type=\"datastream_stream\"' --project=${var.project_id}"
    bigquery_logs = "View BigQuery job history in the Google Cloud Console BigQuery section"
    connectivity_test = "Test source database connectivity from Google Cloud using Cloud Shell or Compute Engine"
    documentation = {
      datastream = "https://cloud.google.com/datastream/docs"
      bigquery = "https://cloud.google.com/bigquery/docs"
      looker_studio = "https://developers.google.com/looker-studio"
    }
  }
}

# Terraform State Information
output "terraform_workspace" {
  description = "Current Terraform workspace information"
  value = {
    workspace = terraform.workspace
    random_suffix = random_id.suffix.hex
    deployment_timestamp = timestamp()
  }
}