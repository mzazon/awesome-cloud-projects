# Main Terraform configuration for Smart Product Review Analysis
# This file creates all the infrastructure needed for multilingual review analysis
# using Google Cloud Translation API, Natural Language AI, Cloud Functions, and BigQuery

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common labels applied to all resources
  common_labels = merge({
    project     = var.project_id
    environment = var.environment
    application = "review-analysis"
    managed-by  = "terraform"
    created-by  = "terraform"
  }, var.additional_labels)

  # Unique resource names with suffix
  resource_suffix = random_id.suffix.hex
  function_name   = "${var.resource_prefix}-function-${local.resource_suffix}"
  dataset_name    = "${replace(var.resource_prefix, "-", "_")}_${local.resource_suffix}"
  bucket_name     = "${var.resource_prefix}-source-${local.resource_suffix}"
  sa_name         = "${var.resource_prefix}-sa-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.apis_to_enable) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = local.sa_name
  display_name = "Service Account for Review Analysis Function"
  description  = "Service account used by Cloud Function for review analysis with Translation and Natural Language APIs"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/cloudsql.client",           # For potential database connections
    "roles/translate.user",            # For Translation API access
    "roles/language.user",             # For Natural Language API access
    "roles/bigquery.dataEditor",       # For BigQuery data manipulation
    "roles/bigquery.jobUser",          # For BigQuery job execution
    "roles/storage.objectViewer",      # For reading function source code
    "roles/logging.logWriter",         # For Cloud Logging
    "roles/monitoring.metricWriter",   # For Cloud Monitoring
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  force_destroy              = true
  project                    = var.project_id

  # Enable versioning for source code management
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  
  source {
    content = <<-EOT
import functions_framework
import json
import logging
from datetime import datetime
from google.cloud import translate_v2 as translate
from google.cloud import language_v1
from google.cloud import bigquery

# Initialize clients
translate_client = translate.Client()
language_client = language_v1.LanguageServiceClient()
bigquery_client = bigquery.Client()

logging.basicConfig(level=logging.INFO)

@functions_framework.http
def analyze_review(request):
    """Analyze product review with translation and sentiment analysis."""
    try:
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid JSON payload'}, 400
        
        review_id = request_json.get('review_id')
        review_text = request_json.get('review_text')
        dataset_id = request_json.get('dataset_id', '${local.dataset_name}')
        
        if not review_id or not review_text:
            return {'error': 'Missing review_id or review_text'}, 400
        
        # Detect source language
        detection = translate_client.detect_language(review_text)
        source_language = detection['language']
        confidence = detection['confidence']
        
        logging.info(f"Detected language: {source_language} (confidence: {confidence})")
        
        # Translate to English if not already English
        translated_text = review_text
        if source_language != 'en':
            translation = translate_client.translate(
                review_text,
                target_language='en',
                source_language=source_language
            )
            translated_text = translation['translatedText']
        
        # Perform sentiment analysis on translated text
        document = language_v1.Document(
            content=translated_text,
            type_=language_v1.Document.Type.PLAIN_TEXT
        )
        
        # Analyze sentiment
        sentiment_response = language_client.analyze_sentiment(
            request={"document": document}
        )
        sentiment = sentiment_response.document_sentiment
        
        # Determine sentiment label
        if sentiment.score > 0.1:
            sentiment_label = 'positive'
        elif sentiment.score < -0.1:
            sentiment_label = 'negative'
        else:
            sentiment_label = 'neutral'
        
        # Extract entities
        entities_response = language_client.analyze_entities(
            request={"document": document}
        )
        
        entities = []
        for entity in entities_response.entities:
            entities.append({
                'name': entity.name,
                'type': entity.type_.name,
                'salience': entity.salience
            })
        
        # Prepare data for BigQuery
        analysis_result = {
            'review_id': review_id,
            'original_text': review_text,
            'original_language': source_language,
            'translated_text': translated_text,
            'sentiment_score': sentiment.score,
            'sentiment_magnitude': sentiment.magnitude,
            'sentiment_label': sentiment_label,
            'entities': json.dumps(entities),
            'processing_timestamp': datetime.utcnow().isoformat()
        }
        
        # Insert into BigQuery
        table_id = 'review_analysis'
        table_ref = bigquery_client.dataset(dataset_id).table(table_id)
        table = bigquery_client.get_table(table_ref)
        
        errors = bigquery_client.insert_rows_json(table, [analysis_result])
        
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
            return {'error': 'Failed to insert data into BigQuery'}, 500
        
        logging.info(f"Successfully processed review {review_id}")
        
        return {
            'status': 'success',
            'review_id': review_id,
            'original_language': source_language,
            'sentiment_label': sentiment_label,
            'sentiment_score': sentiment.score,
            'entities_count': len(entities)
        }
        
    except Exception as e:
        logging.error(f"Error processing review: {str(e)}")
        return {'error': str(e)}, 500
EOT
    filename = "main.py"
  }

  source {
    content = <<-EOT
google-cloud-translate==3.15.5
google-cloud-language==2.13.4
google-cloud-bigquery==3.25.0
functions-framework==3.8.1
EOT
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

# Create BigQuery dataset for review analysis
resource "google_bigquery_dataset" "review_dataset" {
  dataset_id                  = local.dataset_name
  project                     = var.project_id
  friendly_name              = "Product Review Analysis Dataset"
  description                = "Dataset for storing multilingual product review analysis results"
  location                   = var.dataset_location
  default_encryption_configuration {
    kms_key_name = null # Use Google-managed encryption
  }

  # Set default table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.table_expiration_days > 0 ? [1] : []
    content {
      default_table_expiration_ms = var.table_expiration_days * 24 * 60 * 60 * 1000
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for review analysis results
resource "google_bigquery_table" "review_analysis" {
  dataset_id          = google_bigquery_dataset.review_dataset.dataset_id
  table_id           = "review_analysis"
  project            = var.project_id
  deletion_protection = false

  description = "Table storing multilingual review analysis results with sentiment and entity data"

  # Define table schema
  schema = jsonencode([
    {
      name = "review_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the review"
    },
    {
      name = "original_text"
      type = "STRING"
      mode = "REQUIRED"
      description = "Original review text in source language"
    },
    {
      name = "original_language"
      type = "STRING"
      mode = "REQUIRED"
      description = "Detected source language code"
    },
    {
      name = "translated_text"
      type = "STRING"
      mode = "NULLABLE"
      description = "Review text translated to English"
    },
    {
      name = "sentiment_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Sentiment score between -1.0 (negative) and 1.0 (positive)"
    },
    {
      name = "sentiment_magnitude"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Sentiment magnitude indicating emotional intensity"
    },
    {
      name = "sentiment_label"
      type = "STRING"
      mode = "NULLABLE"
      description = "Human-readable sentiment label (positive, negative, neutral)"
    },
    {
      name = "entities"
      type = "STRING"
      mode = "NULLABLE"
      description = "JSON string containing extracted entities and their metadata"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the review was processed"
    }
  ])

  # Time partitioning for query performance and cost optimization
  time_partitioning {
    type  = "DAY"
    field = "processing_timestamp"
  }

  # Clustering for improved query performance
  clustering = ["sentiment_label", "original_language"]

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.review_dataset]
}

# Deploy Cloud Function for review analysis
resource "google_cloudfunctions_function" "review_analyzer" {
  name        = local.function_name
  description = "Processes multilingual product reviews with translation and sentiment analysis"
  runtime     = var.function_runtime
  project     = var.project_id
  region      = var.region

  # Function source configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source_zip.name
  entry_point          = "analyze_review"

  # Resource allocation
  available_memory_mb = var.function_memory
  timeout            = var.function_timeout
  max_instances      = var.max_function_instances

  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  # Environment variables
  environment_variables = {
    PROJECT_ID  = var.project_id
    DATASET_ID  = google_bigquery_dataset.review_dataset.dataset_id
    ENVIRONMENT = var.environment
  }

  # Service account
  service_account_email = google_service_account.function_sa.email

  # Network and security settings
  ingress_settings = var.function_ingress_settings

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source_zip,
    google_project_iam_member.function_sa_roles,
    google_bigquery_table.review_analysis
  ]
}

# IAM policy for function invocation (if authentication not required)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.require_authentication ? 0 : 1

  project        = var.project_id
  region         = google_cloudfunctions_function.review_analyzer.region
  cloud_function = google_cloudfunctions_function.review_analyzer.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"

  depends_on = [google_cloudfunctions_function.review_analyzer]
}

# Create budget for cost monitoring (if enabled)
resource "google_billing_budget" "review_analysis_budget" {
  count = var.budget_amount > 0 ? 1 : 0

  billing_account = data.google_billing_account.account.id
  display_name    = "Review Analysis Budget - ${var.environment}"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    # Filter by labels to include only review analysis resources
    labels = {
      application = "review-analysis"
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  # Configure budget alerts
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Data source for billing account
data "google_billing_account" "account" {
  count = var.budget_amount > 0 ? 1 : 0
  
  # This will use the first available billing account
  # In production, you should specify the exact billing account ID
  open = true
}

# Create Cloud Monitoring alert policy for function errors (if monitoring enabled)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Cloud Function Error Rate - ${local.function_name}"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "The Cloud Function ${local.function_name} is experiencing a high error rate. Check function logs for details."
  }

  depends_on = [
    google_cloudfunctions_function.review_analyzer,
    google_project_service.required_apis
  ]
}

# Create log sink for structured logging (if monitoring enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0

  name                   = "${local.function_name}-logs"
  destination           = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.review_dataset.dataset_id}"
  filter                = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [
    google_cloudfunctions_function.review_analyzer,
    google_bigquery_dataset.review_dataset
  ]
}