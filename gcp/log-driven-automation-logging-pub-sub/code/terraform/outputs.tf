# Outputs for log-driven automation infrastructure

# Project and Environment Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the main Pub/Sub topic for incident automation"
  value       = google_pubsub_topic.incident_automation.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.incident_automation.id
}

output "alert_subscription_name" {
  description = "Name of the alert subscription"
  value       = google_pubsub_subscription.alert_subscription.name
}

output "remediation_subscription_name" {
  description = "Name of the remediation subscription"
  value       = google_pubsub_subscription.remediation_subscription.name
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# Cloud Logging Resources
output "log_sink_name" {
  description = "Name of the log sink forwarding logs to Pub/Sub"
  value       = google_logging_project_sink.automation_sink.name
}

output "log_sink_writer_identity" {
  description = "The writer identity of the log sink"
  value       = google_logging_project_sink.automation_sink.writer_identity
}

output "log_filter" {
  description = "The log filter used by the sink"
  value       = google_logging_project_sink.automation_sink.filter
}

# Log-based Metrics
output "error_rate_metric_name" {
  description = "Name of the error rate log-based metric"
  value       = var.create_log_metrics ? google_logging_metric.error_rate_metric[0].name : null
}

output "exception_pattern_metric_name" {
  description = "Name of the exception pattern log-based metric"
  value       = var.create_log_metrics ? google_logging_metric.exception_pattern_metric[0].name : null
}

output "latency_anomaly_metric_name" {
  description = "Name of the latency anomaly log-based metric"
  value       = var.create_log_metrics ? google_logging_metric.latency_anomaly_metric[0].name : null
}

# Cloud Functions
output "alert_function_name" {
  description = "Name of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processor.name
}

output "alert_function_url" {
  description = "URL of the alert processing Cloud Function"
  value       = google_cloudfunctions2_function.alert_processor.service_config[0].uri
}

output "remediation_function_name" {
  description = "Name of the auto-remediation Cloud Function"
  value       = google_cloudfunctions2_function.auto_remediation.name
}

output "remediation_function_url" {
  description = "URL of the auto-remediation Cloud Function"
  value       = google_cloudfunctions2_function.auto_remediation.service_config[0].uri
}

# Service Accounts
output "alert_function_service_account" {
  description = "Email of the alert function service account"
  value       = var.create_service_accounts ? google_service_account.alert_function_sa[0].email : null
}

output "remediation_function_service_account" {
  description = "Email of the remediation function service account"
  value       = var.create_service_accounts ? google_service_account.remediation_function_sa[0].email : null
}

# Cloud Storage
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the function source bucket"
  value       = google_storage_bucket.function_source.url
}

# Cloud Monitoring
output "error_rate_alert_policy_name" {
  description = "Name of the error rate alerting policy"
  value       = var.create_alerting_policies && var.create_log_metrics ? google_monitoring_alert_policy.error_rate_alert[0].display_name : null
}

output "latency_alert_policy_name" {
  description = "Name of the latency alerting policy"
  value       = var.create_alerting_policies && var.create_log_metrics ? google_monitoring_alert_policy.latency_alert[0].display_name : null
}

output "critical_log_alert_policy_name" {
  description = "Name of the critical log pattern alerting policy"
  value       = var.create_alerting_policies ? google_monitoring_alert_policy.critical_log_pattern_alert[0].display_name : null
}

# Testing and Validation Outputs
output "test_commands" {
  description = "Commands to test the log-driven automation system"
  value = {
    # Command to generate test error log
    generate_test_error = "gcloud logging write test-logs 'Test ERROR message for automation' --severity=ERROR --payload-type=text"
    
    # Command to generate critical log
    generate_critical_log = "gcloud logging write automation-test '{\"severity\": \"CRITICAL\", \"message\": \"OutOfMemoryError in application\", \"service\": \"web-app\", \"instance_id\": \"test-instance\"}' --severity=CRITICAL --payload-type=json"
    
    # Commands to check Pub/Sub subscriptions
    check_alert_subscription = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.alert_subscription.name} --limit=5 --auto-ack"
    check_remediation_subscription = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.remediation_subscription.name} --limit=5 --auto-ack"
    
    # Commands to view function logs
    view_alert_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.alert_processor.name} --limit=10 --region=${var.region}"
    view_remediation_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.auto_remediation.name} --limit=10 --region=${var.region}"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring and observability"
  value = {
    # Cloud Logging queries
    logs_explorer = "https://console.cloud.google.com/logs/query;query=${urlencode(var.log_filter)};duration=PT1H?project=${var.project_id}"
    
    # Pub/Sub monitoring
    pubsub_monitoring = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.incident_automation.name}?project=${var.project_id}"
    
    # Cloud Functions monitoring
    functions_monitoring = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    
    # Cloud Monitoring
    monitoring_dashboard = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    log_filter                   = var.log_filter
    alert_ack_deadline          = "${var.ack_deadline_seconds}s"
    remediation_ack_deadline    = "${var.remediation_ack_deadline_seconds}s"
    function_runtime            = var.function_runtime
    alert_function_memory       = "${var.alert_function_memory}MB"
    remediation_function_memory = "${var.remediation_function_memory}MB"
    error_rate_threshold        = var.error_rate_threshold
    latency_threshold           = "${var.latency_threshold_ms}ms"
    message_retention_duration  = var.message_retention_duration
  }
}

# Security and IAM Information
output "iam_configuration" {
  description = "IAM configuration details"
  value = {
    log_sink_writer_identity = google_logging_project_sink.automation_sink.writer_identity
    alert_function_sa_email  = var.create_service_accounts ? google_service_account.alert_function_sa[0].email : "Default compute service account"
    remediation_function_sa_email = var.create_service_accounts ? google_service_account.remediation_function_sa[0].email : "Default compute service account"
  }
}

# Next Steps and Recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the log-driven automation by generating test error logs using the test_commands",
    "2. Configure external integrations (Slack webhook, email notifications) in function environment variables",
    "3. Monitor function execution logs to verify proper event handling",
    "4. Set up custom alerting policies based on your specific application requirements",
    "5. Review and adjust error rate and latency thresholds based on your application's baseline metrics",
    "6. Implement additional remediation patterns in the auto-remediation function",
    "7. Set up monitoring dashboards to track automation effectiveness",
    "8. Consider implementing circuit breaker patterns to prevent cascading failures during outages"
  ]
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = [
    "1. Monitor Cloud Functions invocation counts and adjust memory allocation if needed",
    "2. Use Pub/Sub message filtering to reduce unnecessary function executions",
    "3. Set appropriate message retention periods based on your requirements",
    "4. Review log ingestion costs and adjust log filters if generating excessive volume",
    "5. Consider using Cloud Functions minimum instances only for critical production workloads",
    "6. Monitor dead letter queue usage to identify and fix message processing issues",
    "7. Use Cloud Monitoring to track resource utilization and right-size instances"
  ]
}