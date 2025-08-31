# Outputs for GCP real-time fraud detection infrastructure
# These outputs provide essential information for system integration and verification

# =============================================================================
# PROJECT AND REGION INFORMATION
# =============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Primary region for fraud detection infrastructure"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# =============================================================================
# CLOUD SPANNER OUTPUTS
# =============================================================================

output "spanner_instance_id" {
  description = "ID of the Cloud Spanner instance for fraud detection"
  value       = google_spanner_instance.fraud_detection.name
}

output "spanner_instance_config" {
  description = "Configuration type of the Spanner instance (multi-region setup)"
  value       = google_spanner_instance.fraud_detection.config
}

output "spanner_processing_units" {
  description = "Number of processing units allocated to the Spanner instance"
  value       = google_spanner_instance.fraud_detection.processing_units
}

output "spanner_database_name" {
  description = "Name of the Spanner database containing fraud detection tables"
  value       = google_spanner_database.fraud_db.name
}

output "spanner_database_state" {
  description = "Current state of the Spanner database"
  value       = google_spanner_database.fraud_db.state
}

output "spanner_connection_string" {
  description = "Connection string for the Spanner database"
  value       = "projects/${var.project_id}/instances/${google_spanner_instance.fraud_detection.name}/databases/${google_spanner_database.fraud_db.name}"
}

# =============================================================================
# PUB/SUB OUTPUTS
# =============================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for transaction events"
  value       = google_pubsub_topic.transaction_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.transaction_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for fraud processing"
  value       = google_pubsub_subscription.fraud_processing.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.fraud_processing.id
}

output "pubsub_dead_letter_topic" {
  description = "Dead letter topic for failed message processing"
  value       = google_pubsub_topic.dead_letter.name
}

# =============================================================================
# CLOUD FUNCTIONS OUTPUTS
# =============================================================================

output "cloud_function_name" {
  description = "Name of the fraud detection Cloud Function"
  value       = google_cloudfunctions2_function.fraud_detector.name
}

output "cloud_function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.fraud_detector.service_config[0].uri
}

output "cloud_function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.fraud_detector.state
}

output "cloud_function_trigger_region" {
  description = "Region where the Cloud Function trigger operates"
  value       = google_cloudfunctions2_function.fraud_detector.event_trigger[0].trigger_region
}

# =============================================================================
# CLOUD STORAGE OUTPUTS
# =============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for fraud detection data"
  value       = google_storage_bucket.fraud_detection_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.fraud_detection_data.url
}

output "function_source_bucket" {
  description = "Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "training_data_object" {
  description = "Cloud Storage object path for ML training data"
  value       = "gs://${google_storage_bucket.fraud_detection_data.name}/${google_storage_bucket_object.training_data.name}"
}

# =============================================================================
# VERTEX AI OUTPUTS
# =============================================================================

output "vertex_ai_dataset_id" {
  description = "ID of the Vertex AI dataset for fraud detection"
  value       = google_vertex_ai_dataset.fraud_detection.name
}

output "vertex_ai_dataset_region" {
  description = "Region where Vertex AI dataset is located"
  value       = google_vertex_ai_dataset.fraud_detection.region
}

output "vertex_ai_dataset_display_name" {
  description = "Display name of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.fraud_detection.display_name
}

# =============================================================================
# SERVICE ACCOUNT OUTPUTS
# =============================================================================

output "function_service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = var.create_service_accounts ? google_service_account.function_sa[0].email : null
}

output "function_service_account_id" {
  description = "Unique ID of the Cloud Function service account"
  value       = var.create_service_accounts ? google_service_account.function_sa[0].unique_id : null
}

# =============================================================================
# MONITORING AND LOGGING OUTPUTS
# =============================================================================

output "log_sink_name" {
  description = "Name of the logging sink for fraud detection events"
  value       = var.enable_audit_logs ? google_logging_project_sink.fraud_detection_sink[0].name : null
}

output "log_sink_writer_identity" {
  description = "Service account email for the logging sink writer"
  value       = var.enable_audit_logs ? google_logging_project_sink.fraud_detection_sink[0].writer_identity : null
}

# =============================================================================
# NETWORK AND SECURITY OUTPUTS
# =============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the fraud detection system"
  value       = var.apis_to_enable
}

output "resource_labels" {
  description = "Common labels applied to all fraud detection resources"
  value       = local.common_labels
}

# =============================================================================
# DATABASE SCHEMA OUTPUTS
# =============================================================================

output "database_tables" {
  description = "List of database tables created for fraud detection"
  value = [
    "Users",
    "Transactions",
    "FraudAlerts"
  ]
}

output "database_indexes" {
  description = "List of database indexes created for performance optimization"
  value = [
    "UserTransactionsByTime",
    "FraudScoreIndex",
    "MerchantTransactionsIndex"
  ]
}

# =============================================================================
# INTEGRATION ENDPOINTS
# =============================================================================

output "transaction_ingestion_commands" {
  description = "Sample commands for publishing transaction events"
  value = {
    gcloud_publish = "gcloud pubsub topics publish ${google_pubsub_topic.transaction_events.name} --message='{\"transaction_id\":\"txn-123\",\"user_id\":\"user-1\",\"amount\":\"150.00\",\"currency\":\"USD\",\"merchant_id\":\"merchant-1\"}'"
    
    curl_publish = "curl -X POST 'https://pubsub.googleapis.com/v1/projects/${var.project_id}/topics/${google_pubsub_topic.transaction_events.name}:publish' -H 'Authorization: Bearer $(gcloud auth print-access-token)' -H 'Content-Type: application/json' -d '{\"messages\":[{\"data\":\"$(echo '{\"transaction_id\":\"txn-123\",\"user_id\":\"user-1\",\"amount\":\"150.00\"}' | base64)\"}]}'"
  }
}

# =============================================================================
# SPANNER QUERY EXAMPLES
# =============================================================================

output "spanner_query_examples" {
  description = "Sample SQL queries for fraud detection analysis"
  value = {
    check_transactions = "SELECT transaction_id, user_id, amount, fraud_score, fraud_prediction FROM Transactions ORDER BY transaction_time DESC LIMIT 10"
    
    high_risk_transactions = "SELECT * FROM Transactions WHERE fraud_score > 0.8 ORDER BY transaction_time DESC"
    
    user_transaction_velocity = "SELECT user_id, COUNT(*) as transaction_count, AVG(amount) as avg_amount FROM Transactions WHERE transaction_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) GROUP BY user_id"
    
    fraud_alerts = "SELECT alert_id, transaction_id, alert_type, severity, description, created_at FROM FraudAlerts WHERE resolved_at IS NULL ORDER BY created_at DESC"
  }
}

# =============================================================================
# COST MONITORING OUTPUTS
# =============================================================================

output "cost_monitoring_info" {
  description = "Information for monitoring costs of fraud detection infrastructure"
  value = {
    spanner_cost_factors = "Processing units (${var.spanner_processing_units}), storage usage, network egress"
    function_cost_factors = "Invocations, compute time, memory allocation (${var.function_memory})"
    storage_cost_factors = "Storage usage, network egress, operations"
    pubsub_cost_factors = "Message volume, subscription usage"
    
    cost_optimization_tips = [
      "Monitor Spanner processing unit utilization and adjust as needed",
      "Review Cloud Function memory allocation and timeout settings",
      "Implement Cloud Storage lifecycle policies for old data",
      "Monitor Pub/Sub message retention and dead letter queue usage"
    ]
  }
}

# =============================================================================
# DEPLOYMENT VERIFICATION
# =============================================================================

output "deployment_verification_commands" {
  description = "Commands to verify successful deployment"
  value = {
    check_spanner = "gcloud spanner instances describe ${google_spanner_instance.fraud_detection.name}"
    check_database = "gcloud spanner databases describe ${google_spanner_database.fraud_db.name} --instance=${google_spanner_instance.fraud_detection.name}"
    check_function = "gcloud functions describe ${google_cloudfunctions2_function.fraud_detector.name} --gen2 --region=${var.region}"
    check_topic = "gcloud pubsub topics describe ${google_pubsub_topic.transaction_events.name}"
    
    test_transaction = "echo '{\"transaction_id\":\"test-$(date +%s)\",\"user_id\":\"user-test\",\"amount\":\"100.00\",\"currency\":\"USD\",\"merchant_id\":\"merchant-test\"}' | gcloud pubsub topics publish ${google_pubsub_topic.transaction_events.name} --message=-"
  }
}

# =============================================================================
# SECURITY AND COMPLIANCE
# =============================================================================

output "security_considerations" {
  description = "Security and compliance information for the fraud detection system"
  value = {
    encryption = "All data encrypted at rest and in transit using Google Cloud default encryption"
    access_control = "IAM-based access control with least privilege principles"
    audit_logging = var.enable_audit_logs ? "Enabled for all fraud detection events" : "Disabled"
    network_security = "Cloud Function configured with internal-only ingress"
    
    compliance_features = [
      "Audit logs for regulatory compliance",
      "Data retention policies in Cloud Storage",
      "Encrypted data storage in Spanner",
      "Service account isolation for components"
    ]
  }
}