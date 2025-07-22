# Outputs for Financial Compliance Monitoring Infrastructure
# This file defines all output values that will be displayed after deployment

# Project and Environment Information
output "project_id" {
  description = "GCP Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# Cloud Spanner Information
output "spanner_instance_id" {
  description = "Cloud Spanner instance ID for compliance monitoring"
  value       = google_spanner_instance.compliance_monitor.name
}

output "spanner_instance_config" {
  description = "Cloud Spanner instance configuration"
  value       = google_spanner_instance.compliance_monitor.config
}

output "spanner_database_id" {
  description = "Cloud Spanner database ID for financial compliance data"
  value       = google_spanner_database.financial_compliance.name
}

output "spanner_instance_state" {
  description = "Current state of the Spanner instance"
  value       = google_spanner_instance.compliance_monitor.state
}

output "spanner_connection_string" {
  description = "Spanner database connection string for applications"
  value       = "projects/${var.project_id}/instances/${google_spanner_instance.compliance_monitor.name}/databases/${google_spanner_database.financial_compliance.name}"
  sensitive   = false
}

# Cloud Tasks Information
output "task_queue_id" {
  description = "Cloud Tasks queue ID for compliance processing"
  value       = google_cloud_tasks_queue.compliance_checks.name
}

output "task_queue_location" {
  description = "Location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.compliance_checks.location
}

output "dead_letter_queue_id" {
  description = "Dead letter queue ID for failed compliance checks"
  value       = google_cloud_tasks_queue.compliance_checks_dlq.name
}

output "task_queue_full_name" {
  description = "Full resource name of the compliance task queue"
  value       = "projects/${var.project_id}/locations/${var.region}/queues/${google_cloud_tasks_queue.compliance_checks.name}"
}

# Cloud Functions Information
output "transaction_processor_url" {
  description = "URL of the transaction processing API"
  value       = google_cloudfunctions2_function.transaction_processor.service_config[0].uri
  sensitive   = false
}

output "compliance_processor_name" {
  description = "Name of the compliance processing function"
  value       = google_cloudfunctions2_function.compliance_processor.name
}

output "compliance_reporter_url" {
  description = "URL of the compliance reporting API"
  value       = google_cloudfunctions2_function.compliance_reporter.service_config[0].uri
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email address of the service account used by functions"
  value       = google_service_account.compliance_processor.email
}

# Pub/Sub Information
output "compliance_events_topic" {
  description = "Pub/Sub topic for compliance events"
  value       = google_pubsub_topic.compliance_events.name
}

output "compliance_events_topic_full_name" {
  description = "Full resource name of the compliance events topic"
  value       = google_pubsub_topic.compliance_events.id
}

# Storage Information
output "compliance_reports_bucket" {
  description = "Cloud Storage bucket for compliance reports"
  value       = google_storage_bucket.compliance_reports.name
}

output "compliance_reports_bucket_url" {
  description = "URL of the compliance reports bucket"
  value       = google_storage_bucket.compliance_reports.url
}

output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Monitoring and Logging Information
output "audit_log_sink_name" {
  description = "Name of the audit log sink (if enabled)"
  value       = var.enable_audit_logs ? google_logging_project_sink.compliance_audit_sink[0].name : null
}

output "monitoring_notification_channel" {
  description = "Monitoring notification channel ID (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].id : null
}

output "budget_id" {
  description = "Billing budget ID for cost monitoring"
  value       = google_billing_budget.compliance_budget.name
}

# API Endpoints for Integration
output "api_endpoints" {
  description = "API endpoints for compliance system integration"
  value = {
    transaction_processor = google_cloudfunctions2_function.transaction_processor.service_config[0].uri
    compliance_reporter   = google_cloudfunctions2_function.compliance_reporter.service_config[0].uri
  }
  sensitive = false
}

# Sample API Usage Commands
output "sample_transaction_command" {
  description = "Sample curl command to submit a transaction"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.transaction_processor.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "account_id": "test-account-001",
        "amount": 5000.00,
        "currency": "USD",
        "source_country": "US",
        "destination_country": "CA",
        "transaction_type": "wire_transfer"
      }'
  EOT
}

output "sample_report_command" {
  description = "Sample curl command to generate a compliance report"
  value = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.compliance_reporter.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "report_type": "daily",
        "jurisdiction": "US"
      }'
  EOT
}

# Database Schema Information
output "database_tables" {
  description = "List of database tables created for compliance monitoring"
  value = [
    "transactions",
    "compliance_checks",
    "regulatory_reports",
    "compliance_rules"
  ]
}

# Compliance Configuration
output "compliance_rules_config" {
  description = "Configured compliance rules and thresholds"
  value = {
    kyc_threshold       = var.compliance_rules.kyc_threshold
    aml_high_risk_score = var.compliance_rules.aml_high_risk_score
    cross_border_limit  = var.compliance_rules.cross_border_limit
    high_risk_countries = var.compliance_rules.high_risk_countries
  }
  sensitive = false
}

# Resource Naming Information
output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    spanner_instance      = google_spanner_instance.compliance_monitor.name
    spanner_database      = google_spanner_database.financial_compliance.name
    task_queue           = google_cloud_tasks_queue.compliance_checks.name
    dead_letter_queue    = google_cloud_tasks_queue.compliance_checks_dlq.name
    service_account      = google_service_account.compliance_processor.account_id
    pubsub_topic         = google_pubsub_topic.compliance_events.name
    reports_bucket       = google_storage_bucket.compliance_reports.name
    function_source_bucket = google_storage_bucket.function_source.name
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    spanner_instance = "~$200-400 (depends on node count and processing units)"
    cloud_functions  = "~$10-50 (depends on invocations and memory usage)"
    cloud_tasks      = "~$1-10 (depends on task volume)"
    storage          = "~$5-20 (depends on data volume)"
    logging          = "~$5-15 (depends on log volume)"
    total_estimate   = "~$221-495 per month"
    note            = "Costs vary based on actual usage and data volumes"
  }
}

# Security Information
output "security_configuration" {
  description = "Security features enabled in the deployment"
  value = {
    audit_logging_enabled     = var.enable_audit_logs
    uniform_bucket_access     = true
    service_account_isolation = true
    iam_least_privilege      = true
    encryption_at_rest       = "Google-managed keys"
    vpc_security            = "Default VPC with firewall rules"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the transaction processing API using the sample command",
    "2. Configure monitoring alerts with appropriate email addresses",
    "3. Set up automated compliance report generation schedules",
    "4. Implement additional security controls for production use",
    "5. Configure backup and disaster recovery procedures",
    "6. Integrate with external KYC/AML providers",
    "7. Set up CI/CD pipelines for function deployments"
  ]
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_spanner_instance = "gcloud spanner instances describe ${google_spanner_instance.compliance_monitor.name}"
    check_database_schema  = "gcloud spanner databases ddl describe ${google_spanner_database.financial_compliance.name} --instance=${google_spanner_instance.compliance_monitor.name}"
    check_task_queue      = "gcloud tasks queues describe ${google_cloud_tasks_queue.compliance_checks.name} --location=${var.region}"
    check_functions       = "gcloud functions describe ${google_cloudfunctions2_function.transaction_processor.name} --region=${var.region} --gen2"
    test_api             = "Use the sample_transaction_command output to test the API"
  }
}