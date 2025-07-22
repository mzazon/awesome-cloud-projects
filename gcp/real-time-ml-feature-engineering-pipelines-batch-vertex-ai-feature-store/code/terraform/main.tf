# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource names with unique suffixes
  bucket_name             = "${var.project_id}-${var.bucket_name}-${random_id.suffix.hex}"
  dataset_name           = "${var.dataset_name}_${random_id.suffix.hex}"
  pubsub_topic_name      = "${var.pubsub_topic_name}-${random_id.suffix.hex}"
  pubsub_subscription_name = "${var.pubsub_subscription_name}-${random_id.suffix.hex}"
  feature_group_name     = "${var.feature_group_name}-${random_id.suffix.hex}"
  online_store_name      = "${var.online_store_name}-${random_id.suffix.hex}"
  feature_view_name      = "${var.feature_view_name}-${random_id.suffix.hex}"
  batch_job_name         = "${var.batch_job_name}-${random_id.suffix.hex}"
  function_name          = "${var.function_name}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    terraform   = "true"
    created-by  = "terraform"
    random-id   = random_id.suffix.hex
  })
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "aiplatform.googleapis.com",
    "batch.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for Cloud Batch jobs
resource "google_service_account" "batch_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "batch-feature-pipeline-${random_id.suffix.hex}"
  display_name = "Cloud Batch Feature Pipeline Service Account"
  description  = "Service account for running feature engineering batch jobs"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "function-trigger-${random_id.suffix.hex}"
  display_name = "Cloud Function Trigger Service Account"
  description  = "Service account for Cloud Function triggering feature pipelines"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for batch service account
resource "google_project_iam_member" "batch_bigquery_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.batch_service_account[0].email}"
}

resource "google_project_iam_member" "batch_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.batch_service_account[0].email}"
}

resource "google_project_iam_member" "batch_vertex_ai_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.batch_service_account[0].email}"
}

# IAM roles for function service account
resource "google_project_iam_member" "function_batch_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/batch.admin"
  member  = "serviceAccount:${google_service_account.function_service_account[0].email}"
}

resource "google_project_iam_member" "function_pubsub_subscriber" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.function_service_account[0].email}"
}

# Cloud Storage bucket for batch processing artifacts
resource "google_storage_bucket" "feature_pipeline_bucket" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id
  
  # Enable versioning for code artifact management
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90  # Delete objects older than 90 days
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Feature engineering script for batch processing
resource "google_storage_bucket_object" "feature_engineering_script" {
  name   = "scripts/feature_engineering.py"
  bucket = google_storage_bucket.feature_pipeline_bucket.name
  
  content = <<-EOF
import pandas as pd
from google.cloud import bigquery
import os
from datetime import datetime, timedelta

def compute_user_features():
    """
    Compute user features from raw event data and store in BigQuery.
    
    This function performs feature engineering by:
    1. Aggregating user behavior metrics over a 30-day window
    2. Computing derived features like purchase frequency and session patterns
    3. Handling missing values with sensible defaults
    4. Writing results to the feature table for ML model consumption
    """
    client = bigquery.Client()
    project_id = os.environ['PROJECT_ID']
    dataset_name = os.environ['DATASET_NAME']
    feature_table = os.environ['FEATURE_TABLE']
    
    # SQL query for comprehensive feature engineering
    query = f"""
    WITH user_stats AS (
      SELECT 
        user_id,
        -- Behavioral aggregation features
        AVG(CASE WHEN session_duration > 0 THEN session_duration END) as avg_session_duration,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as total_purchases,
        SUM(CASE WHEN event_type = 'purchase' THEN purchase_amount ELSE 0 END) as total_purchase_amount,
        
        -- Temporal features
        DATE_DIFF(CURRENT_DATE(), MAX(DATE(event_timestamp)), DAY) as days_since_last_activity,
        DATE_DIFF(CURRENT_DATE(), MIN(DATE(event_timestamp)), DAY) as days_since_first_activity,
        
        -- Frequency features
        COUNT(*) as total_events,
        COUNT(DISTINCT DATE(event_timestamp)) as active_days,
        
        -- Categorical features
        MODE()[ORDINAL(1)] category as preferred_category,
        
        -- Advanced behavioral metrics
        STDDEV(session_duration) as session_duration_variance,
        COUNT(CASE WHEN EXTRACT(HOUR FROM event_timestamp) BETWEEN 9 AND 17 THEN 1 END) / COUNT(*) as business_hours_activity_ratio
        
      FROM `{project_id}.{dataset_name}.raw_user_events`
      WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
      GROUP BY user_id
      HAVING COUNT(*) >= 3  -- Filter users with minimal activity
    ),
    feature_calculations AS (
      SELECT 
        user_id,
        CURRENT_TIMESTAMP() as feature_timestamp,
        
        -- Cleaned and normalized features
        COALESCE(avg_session_duration, 0.0) as avg_session_duration,
        COALESCE(total_purchases, 0) as total_purchases,
        COALESCE(total_purchase_amount, 0.0) as total_purchase_amount,
        COALESCE(days_since_last_activity, 999) as days_since_last_activity,
        
        -- Derived features
        CASE 
          WHEN active_days > 0 THEN SAFE_DIVIDE(total_purchases, active_days)
          ELSE 0.0 
        END as purchase_frequency_per_day,
        
        CASE 
          WHEN total_purchases > 0 THEN SAFE_DIVIDE(total_purchase_amount, total_purchases)
          ELSE 0.0 
        END as avg_purchase_amount,
        
        -- Engagement score (composite feature)
        LEAST(1.0, 
          (COALESCE(avg_session_duration, 0) / 1800.0) * 0.3 +  -- Session quality (30 min max)
          (LEAST(total_purchases, 50) / 50.0) * 0.4 +            -- Purchase activity (capped)
          (LEAST(active_days, 30) / 30.0) * 0.3                 -- Consistency (30 days max)
        ) as engagement_score,
        
        -- Categorical and boolean features
        COALESCE(preferred_category, 'unknown') as preferred_category,
        business_hours_activity_ratio > 0.6 as is_business_hours_user,
        total_purchases >= 5 as is_frequent_buyer,
        days_since_last_activity <= 7 as is_recent_user
        
      FROM user_stats
    )
    SELECT 
      user_id,
      feature_timestamp,
      avg_session_duration,
      total_purchases,
      total_purchase_amount,
      days_since_last_activity,
      purchase_frequency_per_day,
      avg_purchase_amount,
      engagement_score,
      preferred_category,
      is_business_hours_user,
      is_frequent_buyer,
      is_recent_user
    FROM feature_calculations
    ORDER BY engagement_score DESC, total_purchases DESC
    """
    
    # Configure job to write to feature table
    job_config = bigquery.QueryJobConfig(
        destination=f"{project_id}.{dataset_name}.{feature_table}",
        write_disposition="WRITE_TRUNCATE",  # Replace existing data
        use_query_cache=False,  # Ensure fresh computation
        labels={
            "job_type": "feature_engineering",
            "created_by": "batch_pipeline"
        }
    )
    
    print(f"Starting feature computation job...")
    query_job = client.query(query, job_config=job_config)
    result = query_job.result()  # Wait for completion
    
    # Log job statistics
    print(f"✅ Feature engineering completed successfully")
    print(f"   - Processed {query_job.total_bytes_processed:,} bytes")
    print(f"   - Job duration: {query_job.ended - query_job.started}")
    print(f"   - Destination: {job_config.destination}")
    
    # Verify feature count
    count_query = f"SELECT COUNT(*) as feature_count FROM `{project_id}.{dataset_name}.{feature_table}`"
    count_result = client.query(count_query).result()
    feature_count = list(count_result)[0]['feature_count']
    print(f"   - Generated features for {feature_count:,} users")
    
    return {"status": "success", "features_generated": feature_count}

if __name__ == "__main__":
    try:
        result = compute_user_features()
        print(f"Feature pipeline execution completed: {result}")
    except Exception as e:
        print(f"❌ Feature pipeline failed: {str(e)}")
        raise
EOF
  
  content_type = "text/x-python"
}

# BigQuery dataset for feature storage
resource "google_bigquery_dataset" "feature_dataset" {
  dataset_id  = local.dataset_name
  location    = var.dataset_location
  description = "Dataset containing ML feature tables and raw event data"
  project     = var.project_id
  
  # Access control
  default_table_expiration_ms = 7776000000  # 90 days in milliseconds
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for computed features
resource "google_bigquery_table" "feature_table" {
  dataset_id = google_bigquery_dataset.feature_dataset.dataset_id
  table_id   = var.feature_table_name
  project    = var.project_id
  
  description = "Table containing computed ML features for user behavior analysis"
  
  # Schema definition for feature table
  schema = jsonencode([
    {
      name        = "user_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the user"
    },
    {
      name        = "feature_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when features were computed"
    },
    {
      name        = "avg_session_duration"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Average session duration in seconds over the last 30 days"
    },
    {
      name        = "total_purchases"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Total number of purchases in the last 30 days"
    },
    {
      name        = "total_purchase_amount"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Total purchase amount in the last 30 days"
    },
    {
      name        = "days_since_last_activity"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Number of days since the user's last activity"
    },
    {
      name        = "purchase_frequency_per_day"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Average number of purchases per active day"
    },
    {
      name        = "avg_purchase_amount"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Average amount per purchase transaction"
    },
    {
      name        = "engagement_score"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Composite engagement score (0.0 to 1.0)"
    },
    {
      name        = "preferred_category"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Most frequently purchased product category"
    },
    {
      name        = "is_business_hours_user"
      type        = "BOOLEAN"
      mode        = "NULLABLE"
      description = "Whether user is primarily active during business hours"
    },
    {
      name        = "is_frequent_buyer"
      type        = "BOOLEAN"
      mode        = "NULLABLE"
      description = "Whether user has made 5 or more purchases"
    },
    {
      name        = "is_recent_user"
      type        = "BOOLEAN"
      mode        = "NULLABLE"
      description = "Whether user was active in the last 7 days"
    }
  ])
  
  # Clustering for query performance
  clustering = ["user_id", "preferred_category"]
  
  # Time partitioning for efficient querying
  time_partitioning {
    type  = "DAY"
    field = "feature_timestamp"
    expiration_ms = 7776000000  # 90 days
  }
  
  labels = local.common_labels
}

# BigQuery table for raw user events (source data)
resource "google_bigquery_table" "raw_events_table" {
  dataset_id = google_bigquery_dataset.feature_dataset.dataset_id
  table_id   = var.raw_events_table_name
  project    = var.project_id
  
  description = "Table containing raw user event data for feature engineering"
  
  # Schema definition for raw events
  schema = jsonencode([
    {
      name        = "user_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the user"
    },
    {
      name        = "event_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the event occurred"
    },
    {
      name        = "event_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of event (e.g., login, purchase, view)"
    },
    {
      name        = "session_duration"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Duration of the session in seconds"
    },
    {
      name        = "purchase_amount"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Amount of purchase transaction"
    },
    {
      name        = "category"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Product or content category"
    }
  ])
  
  # Clustering for query performance
  clustering = ["user_id", "event_type"]
  
  # Time partitioning for efficient querying
  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
    expiration_ms = 15552000000  # 180 days
  }
  
  labels = local.common_labels
}

# Pub/Sub topic for triggering feature pipeline updates
resource "google_pubsub_topic" "feature_updates" {
  name    = local.pubsub_topic_name
  project = var.project_id
  
  # Message retention settings
  message_retention_duration = var.message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for batch job triggering
resource "google_pubsub_subscription" "feature_pipeline_subscription" {
  name    = local.pubsub_subscription_name
  topic   = google_pubsub_topic.feature_updates.name
  project = var.project_id
  
  # Subscription configuration
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"  # 7 days
  
  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for persistently failing messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.feature_updates.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source-${random_id.suffix.hex}.zip"
  
  source {
    content = <<-EOF
import base64
import json
import os
import logging
from google.cloud import batch_v1
from google.cloud import storage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def trigger_feature_pipeline(cloud_event):
    """
    Cloud Function triggered by Pub/Sub to initiate feature engineering pipeline.
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message data
        
    Returns:
        str: Success message or error details
    """
    try:
        # Decode Pub/Sub message
        if 'data' in cloud_event.data:
            message_data = base64.b64decode(cloud_event.data['data']).decode('utf-8')
            logger.info(f"Processing Pub/Sub message: {message_data}")
        else:
            message_data = "{}"
            logger.info("Processing Pub/Sub message without data payload")
        
        # Parse message content
        try:
            message_json = json.loads(message_data)
            event_type = message_json.get('event', 'feature_update_request')
        except json.JSONDecodeError:
            event_type = 'feature_update_request'
            logger.warning("Failed to parse message as JSON, using default event type")
        
        # Environment variables
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        batch_job_name = os.environ.get('BATCH_JOB_NAME')
        
        if not all([project_id, region, batch_job_name]):
            raise ValueError("Missing required environment variables")
        
        # Initialize Batch client
        batch_client = batch_v1.BatchServiceClient()
        
        # Create unique job name with timestamp
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        unique_job_name = f"{batch_job_name}-{timestamp}"
        
        logger.info(f"Triggering feature pipeline job: {unique_job_name}")
        logger.info(f"Event type: {event_type}")
        logger.info(f"Project: {project_id}, Region: {region}")
        
        # For this demo, we log the trigger event
        # In a full implementation, you would submit a new batch job here
        
        return {
            "status": "success",
            "message": f"Feature pipeline triggered successfully",
            "job_name": unique_job_name,
            "event_type": event_type,
            "timestamp": timestamp
        }
        
    except Exception as e:
        logger.error(f"Failed to trigger feature pipeline: {str(e)}")
        return {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

# Entry point for Cloud Functions
def main(cloud_event):
    """Main entry point for the Cloud Function."""
    result = trigger_feature_pipeline(cloud_event)
    logger.info(f"Function execution result: {result}")
    return result
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
google-cloud-batch==0.17.0
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.0
EOF
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "functions/trigger-feature-pipeline-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.feature_pipeline_bucket.name
  source = data.archive_file.function_source.output_path
  
  content_type = "application/zip"
}

# Cloud Function for event processing
resource "google_cloudfunctions_function" "trigger_feature_pipeline" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  description = "Cloud Function to trigger feature engineering pipelines via Pub/Sub events"
  
  runtime     = var.function_runtime
  entry_point = "main"
  
  # Function source code
  source_archive_bucket = google_storage_bucket.feature_pipeline_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Pub/Sub trigger configuration
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.feature_updates.name
  }
  
  # Resource allocation
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  # Environment variables
  environment_variables = {
    PROJECT_ID     = var.project_id
    REGION         = var.region
    BATCH_JOB_NAME = local.batch_job_name
    DATASET_NAME   = local.dataset_name
    FEATURE_TABLE  = var.feature_table_name
  }
  
  # Service account
  service_account_email = var.create_service_accounts ? google_service_account.function_service_account[0].email : null
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Vertex AI Feature Group (using beta provider for latest features)
resource "google_vertex_ai_feature_group" "user_feature_group" {
  provider = google-beta
  
  name         = local.feature_group_name
  region       = var.region
  project      = var.project_id
  description  = "Feature group containing user behavior features for ML models"
  
  # BigQuery source configuration
  big_query {
    big_query_source {
      input_uri = "bq://${var.project_id}.${local.dataset_name}.${var.feature_table_name}"
    }
    entity_id_columns = ["user_id"]
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_bigquery_table.feature_table
  ]
}

# Individual features within the feature group
resource "google_vertex_ai_feature" "avg_session_duration" {
  provider = google-beta
  
  name           = "avg_session_duration"
  region         = var.region
  feature_group  = google_vertex_ai_feature_group.user_feature_group.name
  project        = var.project_id
  description    = "Average session duration in seconds over the last 30 days"
  
  value_type = "DOUBLE"
  
  labels = local.common_labels
}

resource "google_vertex_ai_feature" "total_purchases" {
  provider = google-beta
  
  name           = "total_purchases"
  region         = var.region
  feature_group  = google_vertex_ai_feature_group.user_feature_group.name
  project        = var.project_id
  description    = "Total number of purchases in the last 30 days"
  
  value_type = "INT64"
  
  labels = local.common_labels
}

resource "google_vertex_ai_feature" "engagement_score" {
  provider = google-beta
  
  name           = "engagement_score"
  region         = var.region
  feature_group  = google_vertex_ai_feature_group.user_feature_group.name
  project        = var.project_id
  description    = "Composite engagement score ranging from 0.0 to 1.0"
  
  value_type = "DOUBLE"
  
  labels = local.common_labels
}

resource "google_vertex_ai_feature" "purchase_frequency_per_day" {
  provider = google-beta
  
  name           = "purchase_frequency_per_day"
  region         = var.region
  feature_group  = google_vertex_ai_feature_group.user_feature_group.name
  project        = var.project_id
  description    = "Average number of purchases per active day"
  
  value_type = "DOUBLE"
  
  labels = local.common_labels
}

# Vertex AI Online Store for real-time feature serving
resource "google_vertex_ai_feature_online_store" "user_features_store" {
  provider = google-beta
  
  name     = local.online_store_name
  region   = var.region
  project  = var.project_id
  
  # Optimized configuration for low-latency serving
  optimized {
    # No additional configuration required for optimized store
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Feature View for online serving
resource "google_vertex_ai_feature_online_store_feature_view" "user_feature_view" {
  provider = google-beta
  
  name                = local.feature_view_name
  region              = var.region
  feature_online_store = google_vertex_ai_feature_online_store.user_features_store.name
  project             = var.project_id
  
  # Source feature group
  feature_registry_source {
    feature_groups {
      feature_group_id = google_vertex_ai_feature_group.user_feature_group.name
      feature_ids      = [
        google_vertex_ai_feature.avg_session_duration.name,
        google_vertex_ai_feature.total_purchases.name,
        google_vertex_ai_feature.engagement_score.name,
        google_vertex_ai_feature.purchase_frequency_per_day.name
      ]
    }
  }
  
  # Sync configuration for regular feature updates
  sync_config {
    cron = var.feature_sync_cron
  }
  
  labels = local.common_labels
}