# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  suffix                   = random_string.suffix.result
  bucket_name             = "${var.resource_prefix}-documents-${local.suffix}"
  topic_name              = "${var.resource_prefix}-events-${local.suffix}"
  results_topic_name      = "${var.resource_prefix}-results-${local.suffix}"
  processing_subscription = "${var.resource_prefix}-process-${local.suffix}"
  results_subscription    = "${var.resource_prefix}-consume-${local.suffix}"
  processor_name          = "${var.processor_display_name}-${local.suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    suffix     = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset(var.api_services) : []
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "20m"
  }
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Document AI Processor for intelligent document extraction
resource "google_document_ai_processor" "form_parser" {
  provider     = google-beta
  location     = var.location
  display_name = local.processor_name
  type         = var.processor_type
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
  
  labels = local.common_labels
  
  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# Cloud Storage bucket for document ingestion
resource "google_storage_bucket" "documents" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning configuration
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age > 0 ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        age = var.bucket_lifecycle_age
      }
    }
  }
  
  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
}

# Pub/Sub topic for document upload events
resource "google_pubsub_topic" "document_events" {
  name    = local.topic_name
  project = var.project_id
  
  message_retention_duration = var.message_retention_duration
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub topic for processing results
resource "google_pubsub_topic" "document_results" {
  name    = local.results_topic_name
  project = var.project_id
  
  message_retention_duration = var.message_retention_duration
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub subscription for document processing
resource "google_pubsub_subscription" "process_documents" {
  name    = local.processing_subscription
  topic   = google_pubsub_topic.document_events.name
  project = var.project_id
  
  ack_deadline_seconds = var.processing_ack_deadline
  
  # Retry policy for failed processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for persistent failures
  dead_letter_policy {
    dead_letter_topic     = "${google_pubsub_topic.document_events.id}-dlq"
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Dead letter topic for failed document processing
resource "google_pubsub_topic" "document_events_dlq" {
  name    = "${local.topic_name}-dlq"
  project = var.project_id
  
  message_retention_duration = "604800s" # 7 days
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub subscription for consuming results
resource "google_pubsub_subscription" "consume_results" {
  name    = local.results_subscription
  topic   = google_pubsub_topic.document_results.name
  project = var.project_id
  
  ack_deadline_seconds = var.results_ack_deadline
  
  # Retry policy for failed consumption
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage notification for triggering processing
resource "google_storage_notification" "document_upload" {
  bucket         = google_storage_bucket.documents.name
  topic          = google_pubsub_topic.document_events.id
  payload_format = "JSON_API_V1"
  
  # Event types that trigger notifications
  event_types = [
    "OBJECT_FINALIZE"
  ]
  
  # Object name prefix filter (optional)
  object_name_prefix = ""
  
  depends_on = [
    google_pubsub_topic_iam_member.storage_publisher,
    google_project_service.apis
  ]
}

# IAM binding for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.document_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.apis]
}

# Firestore database for storing processed results
resource "google_firestore_database" "processed_documents" {
  provider    = google-beta
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location_id
  type        = var.firestore_database_type
  
  # Point-in-time recovery
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # Deletion policy
  delete_protection_state = "DELETE_PROTECTION_DISABLED"
  deletion_policy         = "DELETE"
  
  depends_on = [google_project_service.apis]
}

# Service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "${var.resource_prefix}-functions-${local.suffix}"
  display_name = "Document Intelligence Functions Service Account"
  description  = "Service account for document processing Cloud Functions"
  project      = var.project_id
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.resource_prefix}-functions-${local.suffix}"
  location = var.region
  project  = var.project_id
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
  
  depends_on = [google_project_service.apis]
}

# Archive function source code for document processing
data "archive_file" "process_document_source" {
  type        = "zip"
  output_path = "${path.module}/process-document-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/process_document.py", {
      project_id     = var.project_id
      location       = var.location
      processor_id   = google_document_ai_processor.form_parser.name
      results_topic  = google_pubsub_topic.document_results.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload document processing function source code
resource "google_storage_bucket_object" "process_document_source" {
  name   = "process-document-source-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.process_document_source.output_path
  
  content_type = "application/zip"
}

# Document processing Cloud Function
resource "google_cloudfunctions2_function" "process_document" {
  name        = "${var.resource_prefix}-process-${local.suffix}"
  location    = var.region
  project     = var.project_id
  description = "Process documents with Document AI and publish results"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.process_document_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    available_memory      = "${var.processing_function_memory}M"
    timeout_seconds       = var.processing_function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      PROJECT_ID     = var.project_id
      LOCATION       = var.location
      PROCESSOR_ID   = google_document_ai_processor.form_parser.name
      RESULTS_TOPIC  = google_pubsub_topic.document_results.name
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.document_events.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_project_iam_member.function_storage_viewer,
    google_project_iam_member.function_documentai_user,
    google_project_iam_member.function_pubsub_publisher
  ]
}

# Archive function source code for results consumption
data "archive_file" "consume_results_source" {
  type        = "zip"
  output_path = "${path.module}/consume-results-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/consume_results.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements_consumer.txt")
    filename = "requirements.txt"
  }
}

# Upload results consumer function source code
resource "google_storage_bucket_object" "consume_results_source" {
  name   = "consume-results-source-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.consume_results_source.output_path
  
  content_type = "application/zip"
}

# Results consumer Cloud Function
resource "google_cloudfunctions2_function" "consume_results" {
  name        = "${var.resource_prefix}-consume-${local.suffix}"
  location    = var.region
  project     = var.project_id
  description = "Consume and store Document AI processing results"
  
  build_config {
    runtime     = "python311"
    entry_point = "consume_results"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.consume_results_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    available_memory      = "${var.consumer_function_memory}M"
    timeout_seconds       = var.consumer_function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.document_results.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_project_iam_member.function_firestore_user,
    google_firestore_database.processed_documents
  ]
}

# Create function source files using local files
resource "local_file" "process_document_function" {
  content = templatefile("${path.module}/function_templates/process_document.py.tpl", {
    project_id     = var.project_id
    location       = var.location
    processor_id   = google_document_ai_processor.form_parser.name
    results_topic  = google_pubsub_topic.document_results.name
  })
  filename = "${path.module}/functions/process_document.py"
}

resource "local_file" "consume_results_function" {
  content = templatefile("${path.module}/function_templates/consume_results.py.tpl", {
    project_id = var.project_id
  })
  filename = "${path.module}/functions/consume_results.py"
}

resource "local_file" "processing_requirements" {
  content = <<-EOF
google-cloud-documentai==2.25.0
google-cloud-pubsub==2.21.1
google-cloud-storage==2.14.0
functions-framework==3.5.0
EOF
  filename = "${path.module}/functions/requirements.txt"
}

resource "local_file" "consumer_requirements" {
  content = <<-EOF
google-cloud-firestore==2.14.0
google-cloud-bigquery==3.17.2
functions-framework==3.5.0
EOF
  filename = "${path.module}/functions/requirements_consumer.txt"
}

# Create function template files
resource "local_file" "process_document_template" {
  content = <<-EOF
import base64
import json
import os
from google.cloud import documentai
from google.cloud import pubsub_v1
from google.cloud import storage
import functions_framework

# Initialize clients
document_client = documentai.DocumentProcessorServiceClient()
publisher = pubsub_v1.PublisherClient()
storage_client = storage.Client()

@functions_framework.cloud_event
def process_document(cloud_event):
    """Process uploaded document with Document AI"""
    
    # Parse the Cloud Storage event
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    
    # Skip processing if not a document file
    if not file_name.lower().endswith(('.pdf', '.png', '.jpg', '.jpeg', '.tiff')):
        print(f"Skipping non-document file: {file_name}")
        return
    
    try:
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Configure Document AI request
        processor_name = "${processor_id}"
        
        # Determine document MIME type
        mime_type = "application/pdf" if file_name.lower().endswith('.pdf') else "image/png"
        
        # Process document with Document AI
        document = documentai.Document(
            content=document_content,
            mime_type=mime_type
        )
        
        request = documentai.ProcessRequest(
            name=processor_name,
            document=document
        )
        
        result = document_client.process_document(request=request)
        
        # Extract text and form fields
        extracted_data = {
            "source_file": file_name,
            "bucket": bucket_name,
            "text": result.document.text,
            "pages": len(result.document.pages),
            "form_fields": [],
            "tables": []
        }
        
        # Extract form fields if available
        for page in result.document.pages:
            for form_field in page.form_fields:
                field_name = ""
                field_value = ""
                
                if form_field.field_name:
                    field_name = form_field.field_name.text_anchor.content
                if form_field.field_value:
                    field_value = form_field.field_value.text_anchor.content
                
                extracted_data["form_fields"].append({
                    "name": field_name.strip(),
                    "value": field_value.strip()
                })
        
        # Publish results to Pub/Sub
        results_topic = "${results_topic}"
        message_data = json.dumps(extracted_data).encode('utf-8')
        
        publisher.publish(results_topic, message_data)
        
        print(f"Successfully processed {file_name} and published results")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise
EOF
  filename = "${path.module}/function_templates/process_document.py.tpl"
}

resource "local_file" "consume_results_template" {
  content = <<-EOF
import base64
import json
import functions_framework
from google.cloud import bigquery
from google.cloud import firestore

# Initialize clients
firestore_client = firestore.Client()

@functions_framework.cloud_event
def consume_results(cloud_event):
    """Consume and process Document AI results"""
    
    try:
        # Parse the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        document_data = json.loads(message_data)
        
        # Store results in Firestore for real-time access
        doc_ref = firestore_client.collection('processed_documents').document()
        doc_ref.set({
            'source_file': document_data['source_file'],
            'bucket': document_data['bucket'],
            'text_length': len(document_data['text']),
            'pages': document_data['pages'],
            'form_fields_count': len(document_data['form_fields']),
            'processed_at': firestore.SERVER_TIMESTAMP,
            'form_fields': document_data['form_fields']
        })
        
        # Log processing summary
        print(f"Processed document: {document_data['source_file']}")
        print(f"Pages: {document_data['pages']}")
        print(f"Form fields extracted: {len(document_data['form_fields'])}")
        print(f"Text length: {len(document_data['text'])} characters")
        
        # Example: Extract specific business data
        for field in document_data['form_fields']:
            if 'total' in field['name'].lower() or 'amount' in field['name'].lower():
                print(f"Found financial data - {field['name']}: {field['value']}")
        
        print("✅ Results processed and stored successfully")
        
    except Exception as e:
        print(f"Error consuming results: {str(e)}")
        raise
EOF
  filename = "${path.module}/function_templates/consume_results.py.tpl"
}