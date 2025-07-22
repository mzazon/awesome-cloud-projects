# Smart City Data Processing Infrastructure
# Output values for accessing and managing the deployed resources

#------------------------------------------------------------------------------
# PROJECT AND REGION INFORMATION
#------------------------------------------------------------------------------

output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource naming"
  value       = local.resource_suffix
}

#------------------------------------------------------------------------------
# CLOUD STORAGE OUTPUTS
#------------------------------------------------------------------------------

output "data_lake_bucket_name" {
  description = "Name of the primary data lake Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.name
}

output "data_lake_bucket_url" {
  description = "URL of the primary data lake Cloud Storage bucket"
  value       = google_storage_bucket.data_lake.url
}

output "dataflow_temp_bucket_name" {
  description = "Name of the Dataflow temporary files bucket"
  value       = google_storage_bucket.dataflow_temp.name
}

output "data_lake_folders" {
  description = "List of folders created in the data lake bucket"
  value       = local.data_lake_folders
}

#------------------------------------------------------------------------------
# PUB/SUB OUTPUTS
#------------------------------------------------------------------------------

output "pubsub_topic_names" {
  description = "Map of sensor types to their Pub/Sub topic names"
  value = {
    for topic_key, topic in google_pubsub_topic.sensor_topics : topic_key => topic.name
  }
}

output "pubsub_topic_ids" {
  description = "Map of sensor types to their Pub/Sub topic IDs (full resource names)"
  value = {
    for topic_key, topic in google_pubsub_topic.sensor_topics : topic_key => topic.id
  }
}

output "pubsub_subscription_names" {
  description = "Map of sensor types to their Pub/Sub subscription names"
  value = {
    for sub_key, sub in google_pubsub_subscription.sensor_subscriptions : sub_key => sub.name
  }
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter_topic.name
}

output "pubsub_schemas" {
  description = "Map of sensor types to their Pub/Sub schema names"
  value = {
    for schema_key, schema in google_pubsub_schema.sensor_schemas : schema_key => schema.name
  }
}

#------------------------------------------------------------------------------
# BIGQUERY OUTPUTS
#------------------------------------------------------------------------------

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for smart city analytics"
  value       = google_bigquery_dataset.smart_city_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.smart_city_analytics.location
}

output "bigquery_dataset_url" {
  description = "URL to access the BigQuery dataset in the console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.smart_city_analytics.dataset_id}"
}

output "bigquery_table_names" {
  description = "List of BigQuery table names created for sensor data"
  value = [
    google_bigquery_table.traffic_sensors.table_id,
    google_bigquery_table.air_quality_sensors.table_id,
    google_bigquery_table.energy_consumption.table_id
  ]
}

output "bigquery_materialized_view_name" {
  description = "Name of the materialized view for real-time dashboard"
  value       = google_bigquery_table.real_time_city_dashboard.table_id
}

output "bigquery_data_quality_view_name" {
  description = "Name of the data quality monitoring view"
  value       = google_bigquery_table.data_quality_metrics.table_id
}

output "bigquery_table_ids" {
  description = "Map of sensor types to their BigQuery table IDs"
  value = {
    traffic     = google_bigquery_table.traffic_sensors.id
    air_quality = google_bigquery_table.air_quality_sensors.id
    energy      = google_bigquery_table.energy_consumption.id
    dashboard   = google_bigquery_table.real_time_city_dashboard.id
    data_quality = google_bigquery_table.data_quality_metrics.id
  }
}

#------------------------------------------------------------------------------
# SERVICE ACCOUNT OUTPUTS
#------------------------------------------------------------------------------

output "dataprep_service_account_email" {
  description = "Email address of the Cloud Dataprep service account"
  value       = google_service_account.dataprep_service_account.email
}

output "dataflow_service_account_email" {
  description = "Email address of the Dataflow service account"
  value       = google_service_account.dataflow_service_account.email
}

output "service_account_ids" {
  description = "Map of service account names to their IDs"
  value = {
    dataprep  = google_service_account.dataprep_service_account.id
    dataflow  = google_service_account.dataflow_service_account.id
  }
}

#------------------------------------------------------------------------------
# MONITORING OUTPUTS
#------------------------------------------------------------------------------

output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if configured)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email_notification[0].id : null
}

output "alert_policy_names" {
  description = "List of alert policy names created for monitoring"
  value = concat(
    var.enable_monitoring ? [google_monitoring_alert_policy.low_data_ingestion[0].display_name] : [],
    var.enable_data_quality_monitoring ? [google_monitoring_alert_policy.data_quality_issues[0].display_name] : []
  )
}

#------------------------------------------------------------------------------
# DATA TRANSFER OUTPUTS
#------------------------------------------------------------------------------

output "scheduled_query_transfer_config_id" {
  description = "ID of the scheduled query transfer configuration"
  value       = google_bigquery_data_transfer_config.daily_metrics_transfer.id
}

output "scheduled_query_name" {
  description = "Display name of the scheduled query for daily metrics"
  value       = google_bigquery_data_transfer_config.daily_metrics_transfer.display_name
}

#------------------------------------------------------------------------------
# CONNECTIVITY AND ACCESS INFORMATION
#------------------------------------------------------------------------------

output "gcloud_commands" {
  description = "Useful gcloud commands for interacting with the deployed resources"
  value = {
    # Pub/Sub commands
    publish_traffic_data = "gcloud pubsub topics publish ${google_pubsub_topic.sensor_topics["traffic"].name} --message='{\"sensor_id\":\"TEST001\",\"timestamp\":\"2025-07-12T10:00:00Z\",\"vehicle_count\":125}'"
    
    pull_traffic_messages = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.sensor_subscriptions["traffic"].name} --auto-ack --limit=5"
    
    # BigQuery commands
    query_traffic_data = "bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.smart_city_analytics.dataset_id}.${google_bigquery_table.traffic_sensors.table_id}`'"
    
    query_dashboard_data = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.smart_city_analytics.dataset_id}.${google_bigquery_table.real_time_city_dashboard.table_id}` LIMIT 10'"
    
    # Storage commands  
    list_bucket_contents = "gsutil ls -la gs://${google_storage_bucket.data_lake.name}/"
    
    upload_sample_data = "gsutil cp sample_data.csv gs://${google_storage_bucket.data_lake.name}/raw-data/traffic/"
  }
}

output "console_urls" {
  description = "Direct URLs to access resources in the Google Cloud Console"
  value = {
    # Pub/Sub console URLs
    pubsub_topics = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
    
    # BigQuery console URLs
    bigquery_dataset = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.smart_city_analytics.dataset_id}"
    
    bigquery_dashboard_view = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.smart_city_analytics.dataset_id}!3s${google_bigquery_table.real_time_city_dashboard.table_id}"
    
    # Cloud Storage console URLs
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.data_lake.name}?project=${var.project_id}"
    
    # Monitoring console URLs
    monitoring_dashboard = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    
    # IAM console URLs
    service_accounts = "https://console.cloud.google.com/iam-admin/serviceaccounts?project=${var.project_id}"
  }
}

#------------------------------------------------------------------------------
# CONFIGURATION SUMMARY
#------------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of the deployed smart city data processing infrastructure"
  value = {
    infrastructure_components = {
      data_lake_bucket     = google_storage_bucket.data_lake.name
      bigquery_dataset     = google_bigquery_dataset.smart_city_analytics.dataset_id
      pubsub_topics_count  = length(google_pubsub_topic.sensor_topics)
      bigquery_tables_count = 3
      service_accounts_count = 2
    }
    
    data_sources = {
      traffic_sensors     = "Real-time traffic data from city intersections"
      air_quality_sensors = "Environmental air quality measurements"
      energy_meters       = "Smart meter energy consumption data"
    }
    
    processing_capabilities = {
      real_time_ingestion    = "Pub/Sub topics for high-throughput data ingestion"
      data_warehouse        = "BigQuery for petabyte-scale analytics"
      materialized_views    = "Real-time dashboard with automatic refresh"
      data_quality_monitoring = "Automated quality checks and alerting"
      lifecycle_management  = "Automated data archiving and cost optimization"
    }
    
    monitoring_features = {
      alerting_enabled     = var.enable_monitoring
      data_quality_checks  = var.enable_data_quality_monitoring
      notification_email   = var.notification_email != "" ? "configured" : "not_configured"
      scheduled_reports    = "Daily city metrics aggregation"
    }
  }
}

#------------------------------------------------------------------------------
# NEXT STEPS AND RECOMMENDATIONS
#------------------------------------------------------------------------------

output "next_steps" {
  description = "Recommended next steps for setting up the complete smart city data processing pipeline"
  value = {
    dataprep_setup = [
      "1. Access Cloud Dataprep in the Google Cloud Console",
      "2. Create data flows for each sensor type using the sample data in ${google_storage_bucket.data_lake.name}",
      "3. Configure transformation recipes for data quality improvements",
      "4. Set up automated flow execution triggers"
    ]
    
    data_ingestion = [
      "1. Configure IoT sensors to publish data to the Pub/Sub topics",
      "2. Test data ingestion using the provided gcloud commands",
      "3. Set up Dataflow pipelines for real-time stream processing",
      "4. Validate data quality using the BigQuery monitoring views"
    ]
    
    analytics_setup = [
      "1. Create BigQuery DataCanvas visualizations using the materialized views",
      "2. Build interactive dashboards for city administrators",
      "3. Set up additional scheduled queries for specific analytics needs",
      "4. Configure data export to external BI tools if needed"
    ]
    
    production_readiness = [
      "1. Review and restrict IP access ranges in variables",
      "2. Set up proper backup and disaster recovery procedures",
      "3. Configure additional monitoring and alerting as needed",
      "4. Implement data retention and compliance policies",
      "5. Set up CI/CD pipelines for infrastructure and code deployment"
    ]
  }
}

#------------------------------------------------------------------------------
# COST ESTIMATION
#------------------------------------------------------------------------------

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure (USD)"
  value = {
    note = "Costs vary based on data volume, query frequency, and usage patterns"
    
    components = {
      cloud_storage = "Data lake storage: $10-50/month (depends on data volume and storage class transitions)"
      bigquery_storage = "BigQuery storage: $20-100/month (depends on data volume)"
      bigquery_queries = "BigQuery queries: $50-300/month (depends on query frequency and data processed)"
      pubsub_messaging = "Pub/Sub messaging: $10-50/month (depends on message volume)"
      monitoring = "Cloud Monitoring: $5-20/month (depends on metrics and logs volume)"
      dataflow = "Dataflow (when used): $50-500/month (depends on pipeline complexity and runtime)"
    }
    
    total_estimated_range = "$145-1020/month"
    
    cost_optimization_tips = [
      "Use BigQuery partitioning and clustering for query cost reduction",
      "Implement storage lifecycle policies for automatic cost optimization", 
      "Monitor query patterns and optimize frequently-used queries",
      "Use materialized views to reduce query costs for dashboard updates",
      "Set up budget alerts to monitor spending"
    ]
  }
}