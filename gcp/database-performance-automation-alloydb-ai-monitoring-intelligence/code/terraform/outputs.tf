# Outputs for AlloyDB AI Performance Automation Infrastructure
# These outputs provide essential information for connecting to and managing the deployed resources

# AlloyDB Cluster Information
output "alloydb_cluster_name" {
  description = "Name of the AlloyDB cluster"
  value       = google_alloydb_cluster.main.cluster_id
}

output "alloydb_cluster_id" {
  description = "Full resource ID of the AlloyDB cluster"
  value       = google_alloydb_cluster.main.name
}

output "alloydb_instance_name" {
  description = "Name of the primary AlloyDB instance"
  value       = google_alloydb_instance.primary.instance_id
}

output "alloydb_instance_ip" {
  description = "IP address of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary.ip_address
  sensitive   = false
}

output "alloydb_connection_string" {
  description = "Connection string for the AlloyDB instance (without password)"
  value       = "postgresql://postgres@${google_alloydb_instance.primary.ip_address}:5432/postgres"
  sensitive   = false
}

# Database Authentication Information
output "database_user" {
  description = "Default database user"
  value       = "postgres"
}

output "database_password_secret_name" {
  description = "Name of the Secret Manager secret containing the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "database_password_secret_version" {
  description = "Version of the database password secret"
  value       = google_secret_manager_secret_version.db_password.name
  sensitive   = false
}

# Network Configuration
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.alloydb_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.alloydb_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.alloydb_subnet.name
}

output "subnet_cidr_range" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.alloydb_subnet.ip_cidr_range
}

output "private_service_connection_id" {
  description = "ID of the private service connection"
  value       = google_service_networking_connection.private_vpc_connection.network
}

# Cloud Functions Information
output "performance_optimizer_function_name" {
  description = "Name of the performance optimizer Cloud Function"
  value       = google_cloudfunctions2_function.performance_optimizer.name
}

output "performance_optimizer_function_url" {
  description = "URL of the performance optimizer Cloud Function"
  value       = google_cloudfunctions2_function.performance_optimizer.service_config[0].uri
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

# Pub/Sub and Messaging
output "performance_events_topic_name" {
  description = "Name of the Pub/Sub topic for performance events"
  value       = google_pubsub_topic.performance_events.name
}

output "performance_events_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.performance_events.id
}

# Cloud Storage
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# Vertex AI Resources
output "vertex_ai_dataset_name" {
  description = "Name of the Vertex AI dataset for performance metrics"
  value       = google_vertex_ai_dataset.performance_dataset.display_name
}

output "vertex_ai_dataset_id" {
  description = "ID of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.performance_dataset.name
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are deployed"
  value       = local.vertex_ai_region
}

# Monitoring and Alerting
output "monitoring_dashboard_url" {
  description = "URL to access the AlloyDB performance monitoring dashboard"
  value       = var.monitoring_enabled ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.alloydb_performance[0].id}?project=${var.project_id}" : null
}

output "performance_alert_policy_name" {
  description = "Name of the performance anomaly alert policy"
  value       = var.monitoring_enabled ? google_monitoring_alert_policy.performance_anomaly[0].display_name : null
}

output "custom_metric_type" {
  description = "Type identifier for the custom performance score metric"
  value       = google_monitoring_metric_descriptor.performance_score.type
}

# Scheduling Information
output "performance_analyzer_schedule" {
  description = "Schedule for the performance analyzer job"
  value       = google_cloud_scheduler_job.performance_analyzer.schedule
}

output "daily_report_schedule" {
  description = "Schedule for the daily performance report job"
  value       = google_cloud_scheduler_job.daily_performance_report.schedule
}

output "scheduler_timezone" {
  description = "Timezone for scheduled jobs"
  value       = var.timezone
}

# Resource Identifiers and Metadata
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "deployment_region" {
  description = "Primary region for deployment"
  value       = var.region
}

output "deployment_zone" {
  description = "Primary zone for deployment"
  value       = var.zone
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Cost Monitoring
output "cost_budget_name" {
  description = "Name of the cost monitoring budget"
  value       = var.enable_cost_alerts ? google_billing_budget.alloydb_cost_budget[0].display_name : null
}

output "daily_cost_budget_usd" {
  description = "Daily cost budget in USD"
  value       = var.daily_cost_budget_usd
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to the AlloyDB instance"
  value = <<-EOT
    To connect to your AlloyDB instance:
    
    1. Retrieve the database password:
       gcloud secrets versions access latest --secret="${google_secret_manager_secret.db_password.secret_id}"
    
    2. Connect using psql (requires network access):
       psql "postgresql://postgres:[PASSWORD]@${google_alloydb_instance.primary.ip_address}:5432/postgres"
    
    3. Or connect using Cloud SQL Proxy:
       cloud-sql-proxy --alloydb ${google_alloydb_cluster.main.name}
    
    4. Access the monitoring dashboard:
       ${var.monitoring_enabled ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.alloydb_performance[0].id}?project=${var.project_id}" : "Monitoring not enabled"}
    
    5. View function logs:
       gcloud functions logs read ${google_cloudfunctions2_function.performance_optimizer.name} --gen2 --region=${var.region}
  EOT
}

# Performance Optimization Commands
output "optimization_commands" {
  description = "Commands to trigger performance optimization manually"
  value = <<-EOT
    Manual performance optimization commands:
    
    1. Trigger performance analysis:
       gcloud pubsub topics publish ${google_pubsub_topic.performance_events.name} --message='{"action":"analyze_performance","cluster":"${local.cluster_name}"}'
    
    2. Generate performance report:
       gcloud pubsub topics publish ${google_pubsub_topic.performance_events.name} --message='{"action":"generate_report","cluster":"${local.cluster_name}"}'
    
    3. Check scheduler job status:
       gcloud scheduler jobs describe ${google_cloud_scheduler_job.performance_analyzer.name} --location=${var.region}
    
    4. View recent function executions:
       gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.performance_optimizer.name}" --limit=10 --format="table(timestamp,severity,textPayload)"
  EOT
}

# Security and Access Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    iam_authentication_enabled = var.enable_iam_authentication
    vpc_network                = google_compute_network.alloydb_vpc.name
    private_service_connection = true
    backup_enabled            = var.alloydb_backup_enabled
    backup_retention_days     = var.alloydb_backup_retention_days
    authorized_networks_count = length(var.authorized_networks)
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    alloydb_cluster          = local.cluster_name
    primary_instance         = local.instance_name
    vpc_network             = local.vpc_name
    function_name           = google_cloudfunctions2_function.performance_optimizer.name
    monitoring_enabled      = var.monitoring_enabled
    cost_alerts_enabled     = var.enable_cost_alerts
    vertex_ai_dataset       = google_vertex_ai_dataset.performance_dataset.display_name
    performance_schedule    = var.performance_analysis_schedule
    daily_report_schedule   = var.daily_report_schedule
    total_apis_enabled      = length([for api in google_project_service.required_apis : api.service])
  }
}