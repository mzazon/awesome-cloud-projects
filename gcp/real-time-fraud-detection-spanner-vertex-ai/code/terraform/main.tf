# Real-time Fraud Detection Infrastructure on Google Cloud Platform
# This Terraform configuration deploys a complete fraud detection system
# using Cloud Spanner, Vertex AI, Cloud Functions, and Pub/Sub

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Common resource naming with random suffix
  resource_suffix = random_id.suffix.hex
  
  # Resource names
  spanner_instance_name = "${var.resource_prefix}-instance-${local.resource_suffix}"
  function_name         = "${var.resource_prefix}-processor-${local.resource_suffix}"
  topic_name           = "${var.resource_prefix}-events-${local.resource_suffix}"
  subscription_name    = "${var.resource_prefix}-processing-${local.resource_suffix}"
  bucket_name          = "${var.resource_prefix}-data-${local.resource_suffix}"
  
  # Service account names
  function_sa_name = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    created-by = "terraform"
    resource   = "fraud-detection"
    suffix     = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.apis_to_enable) : []
  
  project = var.project_id
  service = each.value
  
  # Disable dependent services when this resource is destroyed
  disable_dependent_services = true
  
  # Don't disable the service when the resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before creating resources
resource "time_sleep" "api_enablement_delay" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# =============================================================================
# CLOUD SPANNER RESOURCES
# =============================================================================

# Cloud Spanner instance for global fraud detection database
resource "google_spanner_instance" "fraud_detection" {
  depends_on = [time_sleep.api_enablement_delay]
  
  config           = var.spanner_instance_config
  display_name     = var.spanner_instance_display_name
  name             = local.spanner_instance_name
  processing_units = var.spanner_processing_units
  project          = var.project_id
  
  labels = local.common_labels
  
  # Enable deletion protection for production environments
  deletion_protection = var.enable_deletion_protection
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# Spanner database for transaction and fraud data
resource "google_spanner_database" "fraud_db" {
  instance = google_spanner_instance.fraud_detection.name
  name     = var.database_name
  project  = var.project_id
  
  # Enable deletion protection for production environments
  deletion_protection = var.enable_deletion_protection
  
  # Database schema for fraud detection tables
  ddl = [
    # Users table with risk profiling
    <<-EOF
    CREATE TABLE Users (
        user_id STRING(36) NOT NULL,
        email STRING(255),
        created_at TIMESTAMP,
        risk_score FLOAT64,
        country_code STRING(2),
        last_login TIMESTAMP,
        account_status STRING(20),
        verification_level STRING(20)
    ) PRIMARY KEY (user_id)
    EOF
    ,
    # Transactions table interleaved with Users for performance
    <<-EOF
    CREATE TABLE Transactions (
        transaction_id STRING(36) NOT NULL,
        user_id STRING(36) NOT NULL,
        amount NUMERIC,
        currency STRING(3),
        merchant_id STRING(50),
        merchant_category STRING(20),
        transaction_time TIMESTAMP,
        fraud_score FLOAT64,
        fraud_prediction STRING(20),
        ip_address STRING(45),
        device_fingerprint STRING(255),
        processing_status STRING(20),
        created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP()),
        FOREIGN KEY (user_id) REFERENCES Users (user_id)
    ) PRIMARY KEY (transaction_id),
    INTERLEAVE IN PARENT Users ON DELETE CASCADE
    EOF
    ,
    # Index for time-based queries on user transactions
    <<-EOF
    CREATE INDEX UserTransactionsByTime
    ON Transactions (user_id, transaction_time DESC),
    INTERLEAVE IN Users
    EOF
    ,
    # Index for fraud score analysis
    <<-EOF
    CREATE INDEX FraudScoreIndex
    ON Transactions (fraud_score DESC)
    EOF
    ,
    # Index for merchant analysis
    <<-EOF
    CREATE INDEX MerchantTransactionsIndex
    ON Transactions (merchant_id, transaction_time DESC)
    EOF
    ,
    # Fraud alerts table for tracking security events
    <<-EOF
    CREATE TABLE FraudAlerts (
        alert_id STRING(36) NOT NULL,
        transaction_id STRING(36),
        user_id STRING(36),
        alert_type STRING(50),
        severity STRING(20),
        description STRING(1000),
        created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP()),
        resolved_at TIMESTAMP,
        resolution_notes STRING(2000)
    ) PRIMARY KEY (alert_id)
    EOF
  ]
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# =============================================================================
# CLOUD STORAGE RESOURCES
# =============================================================================

# Cloud Storage bucket for ML training data and model artifacts
resource "google_storage_bucket" "fraud_detection_data" {
  depends_on = [time_sleep.api_enablement_delay]
  
  name          = local.bucket_name
  location      = var.storage_bucket_location
  project       = var.project_id
  force_destroy = var.storage_bucket_force_destroy
  
  # Uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = true
  
  # Versioning for data lineage
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for moving old data to cheaper storage
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  labels = local.common_labels
}

# Upload sample training data for ML model
resource "google_storage_bucket_object" "training_data" {
  name   = "training_data.csv"
  bucket = google_storage_bucket.fraud_detection_data.name
  
  # Sample fraud detection training data
  content = <<-EOF
amount,merchant_category,hour_of_day,day_of_week,user_age,transaction_count_1h,fraud_label
25.50,grocery,14,2,32,1,0
1250.00,electronics,23,6,45,1,1
15.75,coffee,8,1,28,3,0
850.00,jewelry,2,0,52,1,1
45.20,gas,17,4,35,2,0
2500.00,travel,22,5,29,1,1
12.99,subscription,10,3,41,1,0
78.45,restaurant,19,5,28,2,0
3500.00,electronics,3,1,25,1,1
22.30,grocery,9,2,45,1,0
EOF
}

# =============================================================================
# PUB/SUB RESOURCES
# =============================================================================

# Pub/Sub topic for transaction events
resource "google_pubsub_topic" "transaction_events" {
  depends_on = [time_sleep.api_enablement_delay]
  
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Message ordering for sequential transaction processing
  message_retention_duration = var.pubsub_message_retention_duration
}

# Pub/Sub subscription for fraud detection processing
resource "google_pubsub_subscription" "fraud_processing" {
  name    = local.subscription_name
  project = var.project_id
  topic   = google_pubsub_topic.transaction_events.name
  
  # Acknowledgment deadline for message processing
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Message retention for debugging and replay
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter queue for problematic messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dlq"
  project = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
}

# =============================================================================
# SERVICE ACCOUNTS AND IAM
# =============================================================================

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.function_sa_name
  display_name = "Fraud Detection Function Service Account"
  description  = "Service account for fraud detection Cloud Functions"
  project      = var.project_id
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "function_spanner_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/spanner.databaseUser"
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
}

resource "google_project_iam_member" "function_vertex_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
}

resource "google_project_iam_member" "function_pubsub_editor" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
}

# =============================================================================
# CLOUD FUNCTIONS
# =============================================================================

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-function-source"
  location      = var.storage_bucket_location
  project       = var.project_id
  force_destroy = var.storage_bucket_force_destroy
  
  uniform_bucket_level_access = true
  labels = local.common_labels
}

# Archive function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/fraud-detection-function.zip"
  
  source {
    content = <<-EOF
import json
import logging
import base64
from google.cloud import spanner
from google.cloud import aiplatform
import functions_framework
import os
from datetime import datetime, timezone

# Initialize Spanner client
spanner_client = spanner.Client()
instance_id = os.environ.get('SPANNER_INSTANCE', '${google_spanner_instance.fraud_detection.name}')
database_id = os.environ.get('DATABASE_NAME', '${var.database_name}')
instance = spanner_client.instance(instance_id)
database = instance.database(database_id)

@functions_framework.cloud_event
def process_transaction(cloud_event):
    """Process incoming transaction for fraud detection."""
    try:
        # Decode Pub/Sub message
        transaction_data = json.loads(
            base64.b64decode(cloud_event.data["message"]["data"]).decode()
        )
        
        logging.info(f"Processing transaction: {transaction_data.get('transaction_id')}")
        
        # Extract transaction details
        user_id = transaction_data.get('user_id')
        amount = float(transaction_data.get('amount', 0))
        merchant_id = transaction_data.get('merchant_id')
        merchant_category = transaction_data.get('merchant_category', 'unknown')
        
        # Calculate fraud score using business rules and ML
        fraud_score = calculate_fraud_score(user_id, amount, merchant_id, merchant_category)
        
        # Store transaction with fraud score
        store_transaction(transaction_data, fraud_score)
        
        # Take action if high fraud risk
        if fraud_score > 0.8:
            create_fraud_alert(transaction_data, fraud_score)
            logging.warning(f"HIGH FRAUD RISK: Transaction {transaction_data.get('transaction_id')} - Score: {fraud_score}")
        
        logging.info(f"Successfully processed transaction {transaction_data.get('transaction_id')} with fraud score {fraud_score}")
        
    except Exception as e:
        logging.error(f"Error processing transaction: {str(e)}", exc_info=True)
        raise

def calculate_fraud_score(user_id, amount, merchant_id, merchant_category):
    """Calculate fraud score using business rules and historical data."""
    base_score = 0.1
    
    # Rule 1: Check for unusual amount
    if amount > 1000:
        base_score += 0.3
    if amount > 5000:
        base_score += 0.4
    
    # Rule 2: Check transaction velocity
    try:
        with database.snapshot() as snapshot:
            velocity_query = """
            SELECT COUNT(*) as transaction_count,
                   AVG(amount) as avg_amount
            FROM Transactions
            WHERE user_id = @user_id
            AND transaction_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
            """
            
            results = snapshot.execute_sql(
                velocity_query, 
                params={'user_id': user_id}
            )
            
            for row in results:
                transaction_count = row[0]
                avg_amount = row[1] if row[1] else 0
                
                # High velocity indicator
                if transaction_count > 5:
                    base_score += 0.4
                elif transaction_count > 2:
                    base_score += 0.2
                
                # Amount deviation indicator
                if avg_amount > 0 and amount > (avg_amount * 5):
                    base_score += 0.3
    
    except Exception as e:
        logging.error(f"Error calculating velocity features: {str(e)}")
        base_score += 0.1  # Conservative increase for query errors
    
    # Rule 3: Merchant category risk
    high_risk_categories = ['jewelry', 'electronics', 'travel', 'gaming']
    if merchant_category.lower() in high_risk_categories:
        base_score += 0.2
    
    # Rule 4: Time-based risk (late night transactions)
    current_hour = datetime.now(timezone.utc).hour
    if current_hour < 6 or current_hour > 23:
        base_score += 0.15
    
    return min(base_score, 1.0)

def store_transaction(transaction_data, fraud_score):
    """Store transaction in Spanner with fraud score."""
    try:
        prediction = 'HIGH_RISK' if fraud_score > 0.8 else 'MEDIUM_RISK' if fraud_score > 0.5 else 'LOW_RISK'
        
        with database.batch() as batch:
            batch.insert(
                table='Transactions',
                columns=[
                    'transaction_id', 'user_id', 'amount', 'currency',
                    'merchant_id', 'merchant_category', 'transaction_time',
                    'fraud_score', 'fraud_prediction', 'ip_address',
                    'device_fingerprint', 'processing_status'
                ],
                values=[
                    [
                        transaction_data.get('transaction_id'),
                        transaction_data.get('user_id'),
                        float(transaction_data.get('amount', 0)),
                        transaction_data.get('currency', 'USD'),
                        transaction_data.get('merchant_id'),
                        transaction_data.get('merchant_category', 'unknown'),
                        spanner.COMMIT_TIMESTAMP,
                        fraud_score,
                        prediction,
                        transaction_data.get('ip_address', ''),
                        transaction_data.get('device_fingerprint', ''),
                        'PROCESSED'
                    ]
                ]
            )
        
        logging.info(f"Transaction stored successfully with fraud score: {fraud_score}")
        
    except Exception as e:
        logging.error(f"Error storing transaction: {str(e)}")
        raise

def create_fraud_alert(transaction_data, fraud_score):
    """Create fraud alert for high-risk transactions."""
    try:
        alert_id = f"alert-{transaction_data.get('transaction_id')}"
        
        with database.batch() as batch:
            batch.insert(
                table='FraudAlerts',
                columns=[
                    'alert_id', 'transaction_id', 'user_id', 'alert_type',
                    'severity', 'description'
                ],
                values=[
                    [
                        alert_id,
                        transaction_data.get('transaction_id'),
                        transaction_data.get('user_id'),
                        'HIGH_FRAUD_SCORE',
                        'HIGH',
                        f"Transaction with fraud score {fraud_score:.3f} exceeds threshold. Amount: {transaction_data.get('amount')} {transaction_data.get('currency', 'USD')}"
                    ]
                ]
            )
        
        logging.info(f"Fraud alert created: {alert_id}")
        
    except Exception as e:
        logging.error(f"Error creating fraud alert: {str(e)}")
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
google-cloud-spanner==3.47.0
google-cloud-aiplatform==1.38.0
google-cloud-pubsub==2.18.4
functions-framework==3.5.0
EOF
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "fraud-detection-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for fraud detection processing
resource "google_cloudfunctions2_function" "fraud_detector" {
  depends_on = [
    google_spanner_database.fraud_db,
    google_pubsub_subscription.fraud_processing
  ]
  
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Real-time fraud detection processor using Spanner and Vertex AI"
  
  build_config {
    runtime     = "python312"
    entry_point = "process_transaction"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    # Environment variables for function configuration
    environment_variables = {
      SPANNER_INSTANCE = google_spanner_instance.fraud_detection.name
      DATABASE_NAME    = var.database_name
      PROJECT_ID       = var.project_id
      REGION          = var.region
    }
    
    # Use custom service account if created
    service_account_email = var.create_service_accounts ? google_service_account.function_sa[0].email : null
    
    # Ingress settings for security
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.transaction_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# =============================================================================
# VERTEX AI RESOURCES (Placeholder for ML Model)
# =============================================================================

# Vertex AI dataset for fraud detection (placeholder)
resource "google_vertex_ai_dataset" "fraud_detection" {
  depends_on = [time_sleep.api_enablement_delay]
  
  display_name          = "fraud-detection-dataset-${local.resource_suffix}"
  metadata_schema_uri   = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region               = var.vertex_ai_region
  project              = var.project_id
  
  labels = local.common_labels
}

# =============================================================================
# MONITORING AND LOGGING
# =============================================================================

# Log sink for fraud detection events
resource "google_logging_project_sink" "fraud_detection_sink" {
  count = var.enable_audit_logs ? 1 : 0
  
  name        = "fraud-detection-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.fraud_detection_data.name}"
  
  # Log filter for fraud-related events
  filter = <<-EOF
    resource.type="cloud_function"
    resource.labels.function_name="${local.function_name}"
    (
      severity>=WARNING OR
      textPayload:"FRAUD" OR
      textPayload:"HIGH_RISK"
    )
    EOF
  
  # Use a unique writer identity for the sink
  unique_writer_identity = true
}

# Grant the log sink permission to write to Cloud Storage
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_audit_logs ? 1 : 0
  
  bucket = google_storage_bucket.fraud_detection_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.fraud_detection_sink[0].writer_identity
}

# =============================================================================
# SAMPLE DATA INSERTION
# =============================================================================

# Sample users data for testing
resource "google_spanner_database_iam_member" "sample_data_user" {
  count = var.create_service_accounts ? 1 : 0
  
  instance = google_spanner_instance.fraud_detection.name
  database = google_spanner_database.fraud_db.name
  role     = "roles/spanner.databaseUser"
  member   = "serviceAccount:${google_service_account.function_sa[0].email}"
}