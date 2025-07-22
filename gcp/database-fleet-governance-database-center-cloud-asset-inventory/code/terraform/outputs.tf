# outputs.tf - Output Values for Database Fleet Governance
# Important resource information and endpoints for the governance solution

# ========================================
# Project and Resource Identification
# ========================================

output "project_id" {
  description = "GCP Project ID where resources are deployed"
  value       = var.project_id
}

output "resource_prefix" {
  description = "Resource naming prefix used for all created resources"
  value       = local.resource_name
}

output "region" {
  description = "GCP region where regional resources are deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# ========================================
# Service Account Information
# ========================================

output "governance_service_account_email" {
  description = "Email address of the database governance service account"
  value       = google_service_account.database_governance.email
}

output "governance_service_account_id" {
  description = "Unique ID of the database governance service account"
  value       = google_service_account.database_governance.unique_id
}

output "custom_iam_role_id" {
  description = "ID of the custom IAM role for database governance"
  value       = google_project_iam_custom_role.database_governance.role_id
}

# ========================================
# Storage and Data Resources
# ========================================

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for governance and asset inventory data"
  value       = google_bigquery_dataset.governance_dataset.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.governance_dataset.location
}

output "storage_bucket_name" {
  description = "Cloud Storage bucket name for compliance reports and exports"
  value       = google_storage_bucket.governance_storage.name
}

output "storage_bucket_url" {
  description = "Cloud Storage bucket URL"
  value       = google_storage_bucket.governance_storage.url
}

# ========================================
# Pub/Sub Resources
# ========================================

output "asset_changes_topic_name" {
  description = "Pub/Sub topic name for database asset change notifications"
  value       = google_pubsub_topic.database_asset_changes.name
}

output "asset_changes_topic_id" {
  description = "Full resource ID of the asset changes topic"
  value       = google_pubsub_topic.database_asset_changes.id
}

output "governance_subscription_name" {
  description = "Pub/Sub subscription name for governance automation"
  value       = google_pubsub_subscription.governance_automation.name
}

output "dead_letter_topic_name" {
  description = "Dead letter topic name for failed message processing"
  value       = google_pubsub_topic.governance_dead_letter.name
}

# ========================================
# Cloud Asset Inventory
# ========================================

output "asset_feed_name" {
  description = "Cloud Asset Inventory feed name for database resources"
  value       = google_cloud_asset_project_feed.database_feed.name
}

output "monitored_asset_types" {
  description = "List of database asset types being monitored"
  value       = local.database_asset_types
}

# ========================================
# Database Fleet Resources (if created)
# ========================================

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name (if created)"
  value       = var.create_sample_databases ? google_sql_database_instance.governance_test_sql[0].name : null
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for private access (if created)"
  value       = var.create_sample_databases ? google_sql_database_instance.governance_test_sql[0].connection_name : null
}

output "spanner_instance_name" {
  description = "Spanner instance name (if created)"
  value       = var.create_sample_databases ? google_spanner_instance.governance_test_spanner[0].name : null
}

output "spanner_database_name" {
  description = "Spanner database name (if created)"
  value       = var.create_sample_databases ? google_spanner_database.governance_test_db[0].name : null
}

output "bigtable_instance_name" {
  description = "Bigtable instance name (if created)"
  value       = var.create_sample_databases ? google_bigtable_instance.governance_test_bigtable[0].name : null
}

# ========================================
# Networking Resources (if created)
# ========================================

output "vpc_network_name" {
  description = "VPC network name for private database connectivity (if created)"
  value       = var.create_sample_databases ? google_compute_network.governance_vpc[0].name : null
}

output "vpc_subnet_name" {
  description = "VPC subnet name for database resources (if created)"
  value       = var.create_sample_databases ? google_compute_subnetwork.governance_subnet[0].name : null
}

output "private_ip_range" {
  description = "Private IP address range for service networking (if created)"
  value       = var.create_sample_databases ? google_compute_global_address.private_ip_address[0].address : null
}

# ========================================
# Automation and Workflow Resources
# ========================================

output "compliance_function_name" {
  description = "Cloud Function name for compliance reporting"
  value       = google_cloudfunctions2_function.compliance_reporter.name
}

output "compliance_function_url" {
  description = "Cloud Function trigger URL"
  value       = google_cloudfunctions2_function.compliance_reporter.service_config[0].uri
}

output "governance_workflow_name" {
  description = "Cloud Workflows name for governance automation"
  value       = google_workflows_workflow.database_governance.name
}

output "governance_workflow_id" {
  description = "Cloud Workflows full resource ID"
  value       = google_workflows_workflow.database_governance.id
}

output "scheduler_job_name" {
  description = "Cloud Scheduler job name for automated governance checks"
  value       = google_cloud_scheduler_job.governance_scheduler.name
}

output "compliance_report_schedule" {
  description = "Cron schedule for compliance report generation"
  value       = var.compliance_report_schedule
}

# ========================================
# Monitoring and Alerting
# ========================================

output "compliance_metric_name" {
  description = "Log-based metric name for database compliance scoring"
  value       = google_logging_metric.database_compliance_score.name
}

output "alert_policy_name" {
  description = "Monitoring alert policy name for governance violations (if created)"
  value       = length(var.alert_email_addresses) > 0 ? google_monitoring_alert_policy.governance_violations[0].display_name : null
}

output "notification_channels" {
  description = "List of email notification channels for governance alerts"
  value       = [for nc in google_monitoring_notification_channel.email_alerts : nc.labels.email_address]
}

output "dashboard_id" {
  description = "Monitoring dashboard ID for database governance (if created)"
  value       = var.enable_dashboard ? google_monitoring_dashboard.governance_dashboard[0].id : null
}

# ========================================
# Security and Compliance Configuration
# ========================================

output "compliance_threshold" {
  description = "Minimum compliance score threshold for alerts"
  value       = var.compliance_threshold
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled for critical resources"
  value       = var.enable_deletion_protection
}

output "uniform_bucket_access_enabled" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_level_access
}

# ========================================
# Database Center Integration Points
# ========================================

output "database_center_url" {
  description = "URL to access Database Center console for AI-powered fleet management"
  value       = "https://console.cloud.google.com/database-center?project=${var.project_id}"
}

output "gemini_chat_instructions" {
  description = "Instructions for using Gemini AI in Database Center"
  value = <<-EOT
    To use Gemini AI for database governance:
    1. Navigate to Database Center: https://console.cloud.google.com/database-center?project=${var.project_id}
    2. Use the Gemini chat interface to ask questions like:
       - "Show me all databases without backup enabled"
       - "Which Cloud SQL instances have public IP access?"
       - "What are the top security recommendations for my database fleet?"
       - "How many databases are compliant with our security policies?"
    3. Review AI-powered insights and recommendations in the dashboard
  EOT
}

# ========================================
# Operational Information
# ========================================

output "manual_setup_required" {
  description = "Manual setup steps required after Terraform deployment"
  value = <<-EOT
    Manual steps to complete database governance setup:
    
    1. Database Center Access:
       - Navigate to ${local.database_center_url}
       - Review fleet health insights and AI recommendations
       - Configure custom governance policies if needed
    
    2. Asset Inventory Verification:
       - Check BigQuery dataset: ${google_bigquery_dataset.governance_dataset.dataset_id}
       - Verify asset feed is receiving database changes
       - Review initial compliance report in Cloud Storage
    
    3. Monitoring Setup:
       - Configure additional alert policies if needed
       - Customize dashboard widgets for specific metrics
       - Set up integration with external ITSM systems
    
    4. Testing and Validation:
       - Create/modify test database resources to trigger workflows
       - Verify compliance reports are generated automatically
       - Test Gemini AI queries in Database Center
  EOT
}

output "useful_commands" {
  description = "Useful gcloud commands for managing the governance solution"
  value = <<-EOT
    Useful commands for database governance management:
    
    # View asset inventory exports
    bq query --use_legacy_sql=false "SELECT * FROM \`${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.asset_inventory\` LIMIT 10"
    
    # Manually trigger governance workflow
    gcloud workflows execute ${google_workflows_workflow.database_governance.name} --data='{"trigger":"manual","project":"${var.project_id}"}' --location=${var.region}
    
    # Check compliance function logs
    gcloud functions logs read ${google_cloudfunctions2_function.compliance_reporter.name} --region=${var.region}
    
    # List database assets using Asset Inventory
    gcloud asset search-all-resources --asset-types='${join(",", local.database_asset_types)}' --project=${var.project_id}
    
    # View Pub/Sub topic messages
    gcloud pubsub subscriptions pull ${google_pubsub_subscription.governance_automation.name} --auto-ack --limit=5
  EOT
}

# ========================================
# Cost Information
# ========================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for governance resources"
  value = <<-EOT
    Estimated monthly costs (USD):
    
    Core Services:
    - BigQuery dataset storage and queries: $5-15
    - Cloud Storage bucket: $1-5
    - Pub/Sub topics and subscriptions: $1-3
    - Cloud Asset Inventory feeds: $0 (included)
    
    Automation:
    - Cloud Functions (2nd gen): $0-5 (depending on execution frequency)
    - Cloud Workflows: $0-2
    - Cloud Scheduler: $0-1
    
    Sample Databases (if enabled):
    - Cloud SQL (db-f1-micro): $7-10
    - Spanner (100 processing units): $30-40
    - Bigtable (1 node development): $65-75
    
    Monitoring:
    - Custom metrics and alerting: $0-3
    - Dashboard and notifications: $0-1
    
    Total estimated cost: $10-20 (core) + $100-125 (with sample databases)
    
    Note: Actual costs may vary based on usage patterns and data volume.
  EOT
}

# Local values for internal use
locals {
  database_center_url = "https://console.cloud.google.com/database-center?project=${var.project_id}"
}