# main.tf
# Main Infrastructure Configuration for Data Privacy Compliance Solution

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming conventions
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-data-${local.resource_suffix}"
  dataset_name    = replace("${var.resource_prefix}_compliance_${local.resource_suffix}", "-", "_")
  function_name   = "${var.resource_prefix}-remediation-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    solution = "data-privacy-compliance"
    version  = "1.0"
  })
}

# ==============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ==============================================================================

# Enable required Google Cloud APIs for the privacy compliance solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "dlp.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ==============================================================================
# CLOUD STORAGE CONFIGURATION
# ==============================================================================

# Cloud Storage bucket for storing data to be scanned by DLP
resource "google_storage_bucket" "dlp_data_bucket" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Enable versioning for data protection and audit trails
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Lifecycle policy for automatic data cleanup
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }

  # Prevent public access to maintain data privacy
  public_access_prevention = var.enable_bucket_public_access_prevention ? "enforced" : "inherited"

  # Enable logging for compliance auditing
  logging {
    log_bucket = google_storage_bucket.audit_logs_bucket.name
  }

  # Apply encryption if KMS key is provided
  dynamic "encryption" {
    for_each = var.kms_key_name != "" ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Separate bucket for audit logs to maintain compliance requirements
resource "google_storage_bucket" "audit_logs_bucket" {
  name                        = "${local.bucket_name}-audit-logs"
  location                    = var.region
  storage_class               = "COLDLINE"
  uniform_bucket_level_access = true

  # Longer retention for audit logs
  lifecycle_rule {
    condition {
      age = 2555 # 7 years for compliance
    }
    action {
      type = "Delete"
    }
  }

  public_access_prevention = "enforced"
  labels                   = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create sample folders in the bucket for data organization
resource "google_storage_bucket_object" "data_folder" {
  bucket  = google_storage_bucket.dlp_data_bucket.name
  name    = "data/"
  content = " " # Empty placeholder content
}

resource "google_storage_bucket_object" "documents_folder" {
  bucket  = google_storage_bucket.dlp_data_bucket.name
  name    = "documents/"
  content = " " # Empty placeholder content
}

# ==============================================================================
# BIGQUERY CONFIGURATION
# ==============================================================================

# BigQuery dataset for storing DLP scan results and compliance analytics
resource "google_bigquery_dataset" "privacy_compliance" {
  dataset_id                 = local.dataset_name
  friendly_name             = "Privacy Compliance and DLP Results"
  description               = "Dataset for storing DLP scan results, compliance metrics, and privacy analytics"
  location                  = var.dataset_location
  delete_contents_on_destroy = false

  # Access controls for the dataset
  access {
    role          = "OWNER"
    user_by_email = "terraform-sa@${var.project_id}.iam.gserviceaccount.com"
  }

  access {
    role   = "READER"
    domain = "your-domain.com" # Replace with your organization domain
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Table for storing detailed DLP scan results
resource "google_bigquery_table" "dlp_scan_results" {
  dataset_id = google_bigquery_dataset.privacy_compliance.dataset_id
  table_id   = "dlp_scan_results"

  description = "Detailed results from Cloud DLP scans including findings, locations, and metadata"

  # Table expiration based on variable
  expiration_time = var.table_expiration_ms > 0 ? var.table_expiration_ms : null

  deletion_protection = var.enable_table_deletion_protection

  schema = jsonencode([
    {
      name        = "scan_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the DLP scan job"
    },
    {
      name        = "file_path"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Full path to the scanned file in Cloud Storage"
    },
    {
      name        = "scan_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the scan was performed"
    },
    {
      name        = "info_type"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Type of sensitive information detected (e.g., EMAIL_ADDRESS, SSN)"
    },
    {
      name        = "likelihood"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Confidence level of the detection (VERY_UNLIKELY to VERY_LIKELY)"
    },
    {
      name        = "quote"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Truncated quote of the detected sensitive data"
    },
    {
      name        = "byte_offset_start"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Starting byte position of the finding in the file"
    },
    {
      name        = "byte_offset_end"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Ending byte position of the finding in the file"
    },
    {
      name        = "finding_count"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of instances of this info type found"
    },
    {
      name        = "compliance_status"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Compliance status: APPROVED, REQUIRES_REVIEW, HIGH_RISK"
    }
  ])

  labels = local.common_labels
}

# Table for storing compliance summary metrics
resource "google_bigquery_table" "compliance_summary" {
  dataset_id = google_bigquery_dataset.privacy_compliance.dataset_id
  table_id   = "compliance_summary"

  description = "Daily summary metrics for privacy compliance monitoring and reporting"

  expiration_time     = var.table_expiration_ms > 0 ? var.table_expiration_ms : null
  deletion_protection = var.enable_table_deletion_protection

  schema = jsonencode([
    {
      name        = "date"
      type        = "DATE"
      mode        = "REQUIRED"
      description = "Date of the compliance summary"
    },
    {
      name        = "total_files_scanned"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Total number of files scanned on this date"
    },
    {
      name        = "files_with_pii"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of files containing personally identifiable information"
    },
    {
      name        = "high_risk_findings"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of high-risk PII findings (LIKELY or VERY_LIKELY)"
    },
    {
      name        = "medium_risk_findings"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of medium-risk PII findings (POSSIBLE)"
    },
    {
      name        = "low_risk_findings"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of low-risk PII findings (UNLIKELY or VERY_UNLIKELY)"
    },
    {
      name        = "compliance_score"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Overall compliance score (0.0 to 100.0)"
    }
  ])

  labels = local.common_labels
}

# ==============================================================================
# PUB/SUB CONFIGURATION
# ==============================================================================

# Pub/Sub topic for DLP notifications and automation triggers
resource "google_pubsub_topic" "dlp_notifications" {
  name = "dlp-notifications-${local.resource_suffix}"

  # Message retention for debugging and compliance
  message_retention_duration = "86400s" # 24 hours

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for the Cloud Function
resource "google_pubsub_subscription" "dlp_function_subscription" {
  name  = "${local.function_name}-subscription"
  topic = google_pubsub_topic.dlp_notifications.name

  # Message acknowledgment deadline
  ack_deadline_seconds = 20

  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlp_dead_letter.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dlp_dead_letter" {
  name   = "dlp-dead-letter-${local.resource_suffix}"
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# CLOUD FUNCTION CONFIGURATION
# ==============================================================================

# Service account for the Cloud Function with appropriate permissions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "DLP Remediation Function Service Account"
  description  = "Service account for the DLP remediation Cloud Function"
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_dlp_user" {
  project = var.project_id
  role    = "roles/dlp.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the function source code as a local file
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = <<EOF
import json
import os
from datetime import datetime
from google.cloud import dlp_v2
from google.cloud import bigquery
from google.cloud import storage
from google.cloud import logging as cloud_logging

def process_dlp_results(event, context):
    """Process DLP scan results and perform automated remediation."""
    
    # Initialize clients
    dlp_client = dlp_v2.DlpServiceClient()
    bq_client = bigquery.Client()
    storage_client = storage.Client()
    logging_client = cloud_logging.Client()
    logger = logging_client.logger("dlp-remediation")
    
    try:
        # Parse the message from Pub/Sub
        import base64
        message_data = json.loads(base64.b64decode(event['data']).decode('utf-8'))
        
        # Extract scan results
        scan_results = message_data.get('findings', [])
        file_path = message_data.get('file_path', '')
        
        # Process each finding
        for finding in scan_results:
            info_type = finding.get('infoType', {}).get('name', '')
            likelihood = finding.get('likelihood', '')
            quote = finding.get('quote', '')
            
            # Insert results into BigQuery
            table_id = f"{os.environ['PROJECT_ID']}.${local.dataset_name}.dlp_scan_results"
            rows_to_insert = [{
                'scan_id': context.eventId,
                'file_path': file_path,
                'scan_timestamp': datetime.utcnow().isoformat(),
                'info_type': info_type,
                'likelihood': likelihood,
                'quote': quote[:100],  # Truncate for privacy
                'byte_offset_start': finding.get('location', {}).get('byteRange', {}).get('start', 0),
                'byte_offset_end': finding.get('location', {}).get('byteRange', {}).get('end', 0),
                'finding_count': 1,
                'compliance_status': 'REQUIRES_REVIEW' if likelihood in ['LIKELY', 'VERY_LIKELY'] else 'APPROVED'
            }]
            
            errors = bq_client.insert_rows_json(table_id, rows_to_insert)
            if errors:
                logger.error(f"BigQuery insert errors: {errors}")
            
            # Implement remediation logic
            if likelihood in ['LIKELY', 'VERY_LIKELY']:
                # High-confidence PII detected - implement quarantine
                bucket_name = file_path.split('/')[2]  # Extract bucket from gs:// path
                blob_name = '/'.join(file_path.split('/')[3:])  # Extract object path
                
                bucket = storage_client.bucket(bucket_name)
                blob = bucket.blob(blob_name)
                
                # Add metadata tag for compliance tracking
                blob.metadata = blob.metadata or {}
                blob.metadata['compliance_status'] = 'HIGH_RISK_PII_DETECTED'
                blob.metadata['scan_timestamp'] = datetime.utcnow().isoformat()
                blob.patch()
                
                logger.warning(f"High-risk PII detected in {file_path}: {info_type}")
        
        return {'status': 'success', 'processed_findings': len(scan_results)}
        
    except Exception as e:
        logger.error(f"Error processing DLP results: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<EOF
google-cloud-dlp==3.12.0
google-cloud-bigquery==3.11.4
google-cloud-storage==2.10.0
google-cloud-logging==3.8.0
EOF
}

# Create a ZIP archive of the function source
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]

  source {
    content  = local_file.function_main.content
    filename = "main.py"
  }

  source {
    content  = local_file.function_requirements.content
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.dlp_data_bucket.name
  source = data.archive_file.function_source.output_path
}

# Deploy the Cloud Function
resource "google_cloudfunctions_function" "dlp_remediation" {
  name        = local.function_name
  description = "Processes DLP scan results and performs automated remediation"
  runtime     = var.function_runtime
  region      = var.region

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  max_instances         = var.function_max_instances
  service_account_email = google_service_account.function_sa.email

  source_archive_bucket = google_storage_bucket.dlp_data_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name

  entry_point = "process_dlp_results"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.dlp_notifications.name
  }

  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = local.dataset_name
    BUCKET_NAME  = local.bucket_name
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# ==============================================================================
# CLOUD DLP CONFIGURATION
# ==============================================================================

# DLP Inspect Template for privacy compliance scanning
resource "google_data_loss_prevention_inspect_template" "privacy_compliance" {
  parent       = "projects/${var.project_id}"
  description  = "DLP inspect template for detecting PII and sensitive data for privacy compliance"
  display_name = "Privacy Compliance Scanner"

  inspect_config {
    # Configure information types to detect
    dynamic "info_types" {
      for_each = var.dlp_info_types
      content {
        name = info_types.value
      }
    }

    # Set minimum likelihood threshold
    min_likelihood = var.dlp_min_likelihood

    # Configure limits
    limits {
      max_findings_per_request = var.dlp_max_findings_per_request

      # Specific limits for high-volume info types
      max_findings_per_info_type {
        info_type {
          name = "EMAIL_ADDRESS"
        }
        max_findings = 100
      }

      max_findings_per_info_type {
        info_type {
          name = "PHONE_NUMBER"
        }
        max_findings = 50
      }
    }

    # Include quotes for context (truncated for privacy)
    include_quote = true
  }

  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# Log-based metric for high-risk PII detections
resource "google_logging_metric" "high_risk_pii_detections" {
  count = var.enable_monitoring ? 1 : 0

  name   = "high_risk_pii_detections"
  filter = <<EOF
resource.type="cloud_function"
resource.labels.function_name="${local.function_name}"
textPayload:"High-risk PII detected"
EOF

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "High Risk PII Detections"
  }

  label_extractors = {
    "info_type" = "EXTRACT(textPayload)"
  }
}

# Alert policy for high-risk PII detections
resource "google_monitoring_alert_policy" "high_risk_pii_alert" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  display_name = "High Risk PII Detection Alert"
  combiner     = "OR"

  conditions {
    display_name = "High Risk PII Detected"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/high_risk_pii_detections\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].id
  ]

  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }
}

# Email notification channel
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0

  display_name = "Privacy Compliance Email Alerts"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

# ==============================================================================
# SECURITY AND COMPLIANCE
# ==============================================================================

# IAM audit configuration for compliance tracking
resource "google_project_iam_audit_config" "privacy_compliance_audit" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id

  service = "dlp.googleapis.com"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Security policy for Cloud Storage bucket
resource "google_storage_bucket_iam_binding" "bucket_security" {
  bucket = google_storage_bucket.dlp_data_bucket.name
  role   = "roles/storage.objectViewer"

  members = [
    "serviceAccount:${google_service_account.function_sa.email}",
  ]
}

# ==============================================================================
# COST MANAGEMENT
# ==============================================================================

# Budget alert for cost management
resource "google_billing_budget" "privacy_compliance_budget" {
  count = var.enable_cost_controls ? 1 : 0

  billing_account = data.google_billing_account.account.id
  display_name    = "Privacy Compliance Solution Budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    services = [
      "services/24E6-581D-38E5", # Cloud DLP
      "services/F25A-F55A-CDF5", # BigQuery
      "services/95FF-2EF5-5EA1", # Cloud Storage
      "services/C12E-C502-C88F", # Cloud Functions
    ]

    labels = {
      solution = "data-privacy-compliance"
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
}

# Get billing account data
data "google_billing_account" "account" {
  billing_account = var.project_id
}

# ==============================================================================
# SAMPLE DATA CREATION (OPTIONAL)
# ==============================================================================

# Create sample CSV file with PII for testing
resource "google_storage_bucket_object" "sample_customer_data" {
  bucket  = google_storage_bucket.dlp_data_bucket.name
  name    = "data/sample_customer_data.csv"
  content = <<EOF
customer_id,name,email,phone,ssn,credit_card,address
1001,John Smith,john.smith@email.com,555-123-4567,123-45-6789,4532-1234-5678-9012,123 Main St
1002,Jane Doe,jane.doe@email.com,555-987-6543,987-65-4321,5555-4444-3333-2222,456 Oak Ave
1003,Bob Johnson,bob.johnson@email.com,555-555-5555,555-55-5555,4111-1111-1111-1111,789 Pine Rd
EOF

  depends_on = [google_storage_bucket.dlp_data_bucket]
}

# Create sample document with mixed PII for testing
resource "google_storage_bucket_object" "sample_privacy_policy" {
  bucket  = google_storage_bucket.dlp_data_bucket.name
  name    = "documents/privacy_policy.txt"
  content = <<EOF
Customer Support Contact Information:
Email: support@company.com
Phone: 1-800-555-0123

For account inquiries, reference your account number: AC-123456789
Social Security verification: 123-45-6789
Payment card ending in: 1111
EOF

  depends_on = [google_storage_bucket.dlp_data_bucket]
}