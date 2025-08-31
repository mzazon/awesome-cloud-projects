# ============================================================================
# Financial Compliance Monitoring with AML AI and BigQuery
# 
# This Terraform configuration creates a comprehensive AML compliance monitoring
# system using Google Cloud services including BigQuery ML, Cloud Functions,
# Pub/Sub, Cloud Scheduler, and Cloud Storage.
# ============================================================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix
  bucket_name    = var.storage_bucket_name != "" ? var.storage_bucket_name : "aml-reports-${random_id.suffix.hex}"
  function_names = {
    alert_processor = "${var.alert_function_name}-${random_id.suffix.hex}"
    report_generator = "${var.report_function_name}-${random_id.suffix.hex}"
  }
  
  # Common labels for all resources
  common_labels = {
    environment    = var.environment
    cost_center   = var.cost_center
    business_unit = var.business_unit
    project       = "aml-compliance"
    managed_by    = "terraform"
  }
  
  # Service account email for Cloud Functions
  function_service_account = "${var.project_id}@appspot.gserviceaccount.com"
}

# ============================================================================
# API ENABLEMENT
# ============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ============================================================================
# BIGQUERY RESOURCES
# ============================================================================

# BigQuery dataset for AML compliance data
resource "google_bigquery_dataset" "aml_compliance" {
  dataset_id                 = var.dataset_id
  friendly_name             = "AML Compliance Data"
  description               = "Dataset containing transaction data and ML models for AML compliance monitoring"
  location                  = var.region
  delete_contents_on_destroy = true
  
  # Access control and security
  access {
    role          = "OWNER"
    user_by_email = local.function_service_account
  }
  
  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }
  
  access {
    role         = "READER"
    special_group = "projectReaders"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Transaction table for storing financial transaction data
resource "google_bigquery_table" "transactions" {
  dataset_id          = google_bigquery_dataset.aml_compliance.dataset_id
  table_id           = var.transaction_table_id
  deletion_protection = false
  
  description = "Table storing financial transaction data for AML analysis"
  
  # Define schema for transaction data
  schema = jsonencode([
    {
      name        = "transaction_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the transaction"
    },
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Transaction timestamp"
    },
    {
      name        = "account_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Account identifier for the transaction source"
    },
    {
      name        = "amount"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Transaction amount"
    },
    {
      name        = "currency"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Currency code (ISO 4217)"
    },
    {
      name        = "transaction_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of transaction (WIRE, ACH, etc.)"
    },
    {
      name        = "counterparty_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Counterparty identifier"
    },
    {
      name        = "country_code"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Country code for transaction jurisdiction"
    },
    {
      name        = "risk_score"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Calculated risk score for the transaction"
    },
    {
      name        = "is_suspicious"
      type        = "BOOLEAN"
      mode        = "REQUIRED"
      description = "Flag indicating if transaction is suspicious"
    }
  ])
  
  # Partitioning for performance optimization
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for query optimization
  clustering = ["country_code", "transaction_type"]
  
  labels = local.common_labels
}

# Compliance alerts table for tracking AML alerts and investigations
resource "google_bigquery_table" "compliance_alerts" {
  dataset_id          = google_bigquery_dataset.aml_compliance.dataset_id
  table_id           = var.alerts_table_id
  deletion_protection = false
  
  description = "Table storing AML compliance alerts and investigation status"
  
  # Define schema for compliance alerts
  schema = jsonencode([
    {
      name        = "alert_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the alert"
    },
    {
      name        = "transaction_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Related transaction identifier"
    },
    {
      name        = "risk_score"
      type        = "NUMERIC"
      mode        = "REQUIRED"
      description = "Risk score that triggered the alert"
    },
    {
      name        = "alert_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "When the alert was generated"
    },
    {
      name        = "status"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Investigation status (OPEN, INVESTIGATING, CLOSED)"
    },
    {
      name        = "investigator"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Assigned investigator"
    },
    {
      name        = "resolution"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Alert resolution details"
    },
    {
      name        = "resolution_timestamp"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "When the alert was resolved"
    }
  ])
  
  # Partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "alert_timestamp"
  }
  
  labels = local.common_labels
}

# Sample transaction data for testing and demonstration
resource "google_bigquery_job" "load_sample_data" {
  count = var.load_sample_data ? 1 : 0
  
  job_id = "load-sample-transactions-${random_id.suffix.hex}"
  
  load {
    source_uris = []
    
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.aml_compliance.dataset_id
      table_id   = google_bigquery_table.transactions.table_id
    }
    
    write_disposition = "WRITE_APPEND"
    source_format     = "NEWLINE_DELIMITED_JSON"
    
    # Sample transaction data
    # In production, this would be loaded from external data sources
  }
  
  depends_on = [google_bigquery_table.transactions]
}

# BigQuery ML model for AML detection
resource "google_bigquery_job" "create_ml_model" {
  count = var.create_ml_model ? 1 : 0
  
  job_id = "create-aml-model-${random_id.suffix.hex}"
  
  query {
    query = <<-EOT
      CREATE OR REPLACE MODEL `${var.project_id}.${var.dataset_id}.${var.ml_model_id}`
      OPTIONS(
        model_type='logistic_reg',
        input_label_cols=['is_suspicious'],
        auto_class_weights=true
      ) AS
      SELECT
        amount,
        risk_score,
        CASE 
          WHEN transaction_type = 'WIRE' THEN 1 
          ELSE 0 
        END AS is_wire_transfer,
        CASE 
          WHEN country_code = 'XX' THEN 1 
          ELSE 0 
        END AS is_high_risk_country,
        is_suspicious
      FROM `${var.project_id}.${var.dataset_id}.${var.transaction_table_id}`
      WHERE is_suspicious IS NOT NULL
    EOT
    
    use_legacy_sql = false
  }
  
  depends_on = [
    google_bigquery_table.transactions,
    google_bigquery_job.load_sample_data
  ]
}

# ============================================================================
# PUB/SUB RESOURCES
# ============================================================================

# Pub/Sub topic for AML alerts
resource "google_pubsub_topic" "aml_alerts" {
  name = var.pubsub_topic_name
  
  labels = local.common_labels
  
  # Message retention for compliance
  message_retention_duration = var.message_retention_duration
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub subscription for alert processing
resource "google_pubsub_subscription" "aml_alerts" {
  name  = var.pubsub_subscription_name
  topic = google_pubsub_topic.aml_alerts.name
  
  # Message acknowledgment deadline
  ack_deadline_seconds = 60
  
  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Dead letter queue for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.aml_alerts_dlq.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Dead letter queue for failed alert processing
resource "google_pubsub_topic" "aml_alerts_dlq" {
  name = "${var.pubsub_topic_name}-dlq"
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
}

# ============================================================================
# CLOUD STORAGE RESOURCES
# ============================================================================

# Cloud Storage bucket for compliance reports
resource "google_storage_bucket" "compliance_reports" {
  name     = local.bucket_name
  location = var.storage_location
  
  # Security and compliance settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for compliance retention
  lifecycle_rule {
    condition {
      age = var.report_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Move to nearline storage after 30 days for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Move to coldline storage after 90 days
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Encryption configuration
  dynamic "encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      default_kms_key_name = google_kms_crypto_key.bucket_key[0].id
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# KMS key for bucket encryption (if enabled)
resource "google_kms_key_ring" "compliance" {
  count = var.enable_encryption ? 1 : 0
  
  name     = "aml-compliance-${random_id.suffix.hex}"
  location = var.region
}

resource "google_kms_crypto_key" "bucket_key" {
  count = var.enable_encryption ? 1 : 0
  
  name     = "compliance-reports-key"
  key_ring = google_kms_key_ring.compliance[0].id
  
  purpose = "ENCRYPT_DECRYPT"
  
  labels = local.common_labels
}

# ============================================================================
# CLOUD FUNCTIONS
# ============================================================================

# Cloud Function source code archives
data "archive_file" "alert_function_source" {
  type        = "zip"
  output_path = "/tmp/alert-function-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/alert_processor.py", {
      project_id = var.project_id
      dataset_id = var.dataset_id
    })
    filename = "main.py"
  }
  
  source {
    content = <<-EOT
      google-cloud-bigquery==3.15.0
      google-cloud-monitoring==2.18.0
      functions-framework==3.5.0
    EOT
    filename = "requirements.txt"
  }
}

data "archive_file" "report_function_source" {
  type        = "zip"
  output_path = "/tmp/report-function-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/report_generator.py", {
      project_id  = var.project_id
      dataset_id  = var.dataset_id
      bucket_name = local.bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content = <<-EOT
      google-cloud-bigquery==3.15.0
      google-cloud-storage==2.12.0
      pandas==2.1.4
      functions-framework==3.5.0
    EOT
    filename = "requirements.txt"
  }
}

# Storage buckets for function source code
resource "google_storage_bucket" "function_source" {
  name     = "aml-function-source-${random_id.suffix.hex}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
  
  depends_on = [google_project_service.apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "alert_function_source" {
  name   = "alert-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.alert_function_source.output_path
}

resource "google_storage_bucket_object" "report_function_source" {
  name   = "report-generator-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.report_function_source.output_path
}

# Cloud Function for AML alert processing
resource "google_cloudfunctions2_function" "alert_processor" {
  name        = local.function_names.alert_processor
  location    = var.region
  description = "Processes AML alerts from Pub/Sub and logs to BigQuery"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_aml_alert"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.alert_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.alert_function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = local.function_service_account
    
    environment_variables = {
      PROJECT_ID = var.project_id
      DATASET_ID = var.dataset_id
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.aml_alerts.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Function for compliance report generation
resource "google_cloudfunctions2_function" "report_generator" {
  name        = local.function_names.report_generator
  location    = var.region
  description = "Generates daily compliance reports and stores them in Cloud Storage"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "generate_compliance_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.report_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 3
    min_instance_count    = 0
    available_memory      = "${var.report_function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = local.function_service_account
    
    environment_variables = {
      PROJECT_ID  = var.project_id
      DATASET_ID  = var.dataset_id
      BUCKET_NAME = local.bucket_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# ============================================================================
# CLOUD SCHEDULER
# ============================================================================

# Cloud Scheduler job for automated compliance reporting
resource "google_cloud_scheduler_job" "compliance_report" {
  name             = var.scheduler_job_name
  description      = "Daily AML compliance report generation"
  schedule         = var.report_schedule
  time_zone        = var.scheduler_timezone
  attempt_deadline = "300s"
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "0s"
    max_backoff_duration = "300s"
    min_backoff_duration = "60s"
    max_doublings        = 2
  }
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    oidc_token {
      service_account_email = local.function_service_account
    }
  }
  
  depends_on = [google_project_service.apis]
}

# ============================================================================
# IAM PERMISSIONS
# ============================================================================

# BigQuery permissions for Cloud Functions
resource "google_project_iam_member" "function_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${local.function_service_account}"
}

# Cloud Storage permissions for Cloud Functions
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${local.function_service_account}"
}

# Pub/Sub permissions for Cloud Functions
resource "google_project_iam_member" "function_pubsub_viewer" {
  project = var.project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${local.function_service_account}"
}

# Cloud Functions invoker permissions for Cloud Scheduler
resource "google_cloud_scheduler_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  job      = google_cloud_scheduler_job.compliance_report.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.function_service_account}"
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Monitoring notification channel (email)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AML Compliance Email Alerts"
  type         = "email"
  
  labels = {
    email_address = "compliance-team@example.com"  # Replace with actual email
  }
}

# Alert policy for function failures
resource "google_monitoring_alert_policy" "function_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AML Function Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "Function execution failures"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.label.status!=\"ok\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
}

# Alert policy for high-risk transactions
resource "google_monitoring_alert_policy" "high_risk_transactions" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Risk Transaction Volume"
  combiner     = "OR"
  
  conditions {
    display_name = "High volume of suspicious transactions"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_topic\" AND metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
}

# ============================================================================
# DATA INITIALIZATION (Sample Data)
# ============================================================================

# Sample transaction data for testing
resource "google_bigquery_table" "sample_data_temp" {
  count = var.load_sample_data ? 1 : 0
  
  dataset_id          = google_bigquery_dataset.aml_compliance.dataset_id
  table_id           = "sample_transactions_temp"
  deletion_protection = false
  
  schema = google_bigquery_table.transactions.schema
  
  # This will be populated via external_data_configuration or load job
  # Sample data would be inserted here in a real deployment
}

# ============================================================================
# FUNCTION SOURCE CODE FILES
# ============================================================================

# Create function code files
resource "local_file" "alert_processor_code" {
  filename = "${path.module}/function_code/alert_processor.py"
  content = <<-EOT
import json
import logging
import os
from google.cloud import bigquery
from google.cloud import monitoring_v3

def process_aml_alert(cloud_event):
    """Process AML alert from Pub/Sub"""
    try:
        # Decode the CloudEvent message
        import base64
        message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        alert_data = json.loads(message_data)
        
        logging.info(f"Processing AML alert: {alert_data}")
        
        # Initialize BigQuery client
        client = bigquery.Client()
        
        project_id = os.environ.get('PROJECT_ID', '${var.project_id}')
        dataset_id = os.environ.get('DATASET_ID', '${var.dataset_id}')
        
        # Log alert to compliance table
        query = f"""
        INSERT INTO `{project_id}.{dataset_id}.compliance_alerts`
        (alert_id, transaction_id, risk_score, alert_timestamp, status)
        VALUES (
            GENERATE_UUID(),
            '{alert_data.get('transaction_id', 'UNKNOWN')}',
            {alert_data.get('risk_score', 0.0)},
            CURRENT_TIMESTAMP(),
            'OPEN'
        )
        """
        
        job = client.query(query)
        job.result()
        
        logging.info(f"AML alert processed successfully: {alert_data.get('transaction_id', 'UNKNOWN')}")
        
        return "Alert processed"
        
    except Exception as e:
        logging.error(f"Error processing AML alert: {e}")
        raise
EOT
}

resource "local_file" "report_generator_code" {
  filename = "${path.module}/function_code/report_generator.py"
  content = <<-EOT
import json
import os
from datetime import datetime, timedelta
from google.cloud import bigquery
from google.cloud import storage

def generate_compliance_report(request):
    """Generate daily compliance report"""
    try:
        client = bigquery.Client()
        storage_client = storage.Client()
        
        project_id = os.environ.get('PROJECT_ID', '${var.project_id}')
        dataset_id = os.environ.get('DATASET_ID', '${var.dataset_id}')
        bucket_name = os.environ.get('BUCKET_NAME', '${local.bucket_name}')
        
        # Generate report for previous day
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        
        # Query suspicious transactions
        query = f"""
        SELECT 
            transaction_id,
            timestamp,
            account_id,
            amount,
            currency,
            risk_score,
            country_code
        FROM `{project_id}.{dataset_id}.transactions`
        WHERE DATE(timestamp) = '{yesterday}'
          AND is_suspicious = true
        ORDER BY risk_score DESC
        """
        
        results = client.query(query).to_dataframe()
        
        # Generate report content
        report_content = f"""
AML Compliance Report - {yesterday}

Total Suspicious Transactions: {len(results)}
High Risk Transactions (>0.8): {len(results[results['risk_score'] > 0.8]) if len(results) > 0 else 0}

Detailed Transactions:
{results.to_string(index=False) if len(results) > 0 else 'No suspicious transactions found'}

Generated: {datetime.now().isoformat()}
        """
        
        # Upload report to Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(f'compliance-reports/aml-report-{yesterday}.txt')
        blob.upload_from_string(report_content)
        
        print(f"Compliance report generated for {yesterday}")
        return f"Report generated for {yesterday}", 200
        
    except Exception as e:
        print(f"Error generating compliance report: {e}")
        return f"Error generating report: {str(e)}", 500
EOT
}