# Smart Form Processing with Document AI and Gemini - Main Infrastructure
# This configuration creates a complete intelligent document processing system using
# Google Cloud's Document AI, Vertex AI Gemini, Cloud Functions, and Cloud Storage

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and labeling
  name_prefix = "${var.environment}-smart-forms"
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    purpose     = "document-processing"
  })

  # Resource names with random suffix for global uniqueness
  input_bucket_name  = "${local.name_prefix}-input-${random_id.suffix.hex}"
  output_bucket_name = "${local.name_prefix}-output-${random_id.suffix.hex}"
  function_name      = "${var.function_name}-${random_id.suffix.hex}"
}

# ================================
# Google Cloud APIs
# ================================

# Enable required Google Cloud APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",   # Cloud Functions
    "documentai.googleapis.com",       # Document AI
    "aiplatform.googleapis.com",       # Vertex AI (for Gemini)
    "storage.googleapis.com",          # Cloud Storage
    "cloudbuild.googleapis.com",       # Cloud Build (for function deployment)
    "eventarc.googleapis.com",         # Eventarc (for storage triggers)
    "run.googleapis.com",              # Cloud Run (required for Gen2 functions)
    "artifactregistry.googleapis.com", # Artifact Registry (for function containers)
    "logging.googleapis.com",          # Cloud Logging
    "monitoring.googleapis.com"        # Cloud Monitoring
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ================================
# Service Accounts and IAM
# ================================

# Service account for Cloud Function with necessary permissions
resource "google_service_account" "function_sa" {
  account_id   = "${local.name_prefix}-function-sa"
  display_name = "Smart Form Processing Function Service Account"
  description  = "Service account for the form processing Cloud Function with Document AI and Vertex AI access"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM binding for Document AI access
resource "google_project_iam_member" "function_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Vertex AI access
resource "google_project_iam_member" "function_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Storage access
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Logging
resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Monitoring
resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ================================
# Cloud Storage Buckets
# ================================

# Input bucket for form uploads with storage trigger
resource "google_storage_bucket" "input_bucket" {
  name     = local.input_bucket_name
  location = var.region
  project  = var.project_id

  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Labels for resource management
  labels = local.common_labels

  # Lifecycle management to control storage costs
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # Encryption configuration
  encryption {
    default_kms_key_name = null # Uses Google-managed encryption keys
  }

  depends_on = [google_project_service.required_apis]
}

# Output bucket for processed results
resource "google_storage_bucket" "output_bucket" {
  name     = local.output_bucket_name
  location = var.region
  project  = var.project_id

  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Labels for resource management
  labels = local.common_labels

  # Lifecycle management to control storage costs
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # Encryption configuration
  encryption {
    default_kms_key_name = null # Uses Google-managed encryption keys
  }

  depends_on = [google_project_service.required_apis]
}

# ================================
# Document AI Processor
# ================================

# Document AI processor for form parsing
resource "google_document_ai_processor" "form_parser" {
  location     = var.region
  display_name = var.document_ai_processor_display_name
  type         = var.document_ai_processor_type
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# ================================
# Cloud Function Source Code
# ================================

# Create the function source code files
resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOT
google-cloud-documentai==2.30.0
google-cloud-aiplatform==1.71.0
google-cloud-storage==2.18.0
google-auth==2.34.0
functions-framework==3.8.1
vertexai==1.71.0
EOT
}

resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = <<-EOT
import json
import os
from google.cloud import documentai
from google.cloud import aiplatform
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

# Initialize clients
storage_client = storage.Client()
docai_client = documentai.DocumentProcessorServiceClient()

def process_document_ai(file_content, processor_name):
    """Extract data using Document AI Form Parser"""
    # Create Document AI request
    raw_document = documentai.RawDocument(
        content=file_content,
        mime_type="application/pdf"
    )
    
    request = documentai.ProcessRequest(
        name=processor_name,
        raw_document=raw_document
    )
    
    # Process document
    result = docai_client.process_document(request=request)
    document = result.document
    
    # Extract form fields
    form_fields = {}
    for page in document.pages:
        for form_field in page.form_fields:
            field_name = form_field.field_name.text_anchor.content if form_field.field_name else "unknown"
            field_value = form_field.field_value.text_anchor.content if form_field.field_value else ""
            form_fields[field_name.strip()] = field_value.strip()
    
    # Calculate average confidence
    total_confidence = 0
    field_count = 0
    for page in document.pages:
        for form_field in page.form_fields:
            if form_field.field_value.confidence:
                total_confidence += form_field.field_value.confidence
                field_count += 1
    
    avg_confidence = total_confidence / field_count if field_count > 0 else 0.0
    
    return {
        "extracted_text": document.text,
        "form_fields": form_fields,
        "confidence": avg_confidence
    }

def validate_with_gemini(extracted_data):
    """Validate and enrich data using Gemini"""
    # Initialize Vertex AI
    vertexai.init(
        project=os.environ.get('GCP_PROJECT'), 
        location=os.environ.get('FUNCTION_REGION')
    )
    
    model = GenerativeModel(os.environ.get('VERTEX_AI_MODEL', 'gemini-1.5-flash'))
    
    prompt = f"""
    Analyze this extracted form data and provide validation and enrichment:
    
    Extracted Data: {json.dumps(extracted_data, indent=2)}
    
    Please provide:
    1. Data validation (check for completeness, format errors, inconsistencies)
    2. Data enrichment (suggest corrections, standardize formats)
    3. Confidence score (1-10) for overall data quality
    4. Specific issues found and recommendations
    
    Return response as JSON with keys: validation_results, enriched_data, confidence_score, recommendations
    """
    
    response = model.generate_content(prompt)
    
    try:
        # Parse Gemini response as JSON
        gemini_analysis = json.loads(response.text)
        return gemini_analysis
    except json.JSONDecodeError:
        # Fallback if response isn't valid JSON
        return {
            "validation_results": "Analysis completed",
            "enriched_data": extracted_data,
            "confidence_score": 7,
            "recommendations": response.text
        }

@functions_framework.cloud_event
def process_form(cloud_event):
    """Main Cloud Function triggered by Cloud Storage"""
    # Get file information from event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    if not file_name.endswith('.pdf'):
        print(f"Skipping non-PDF file: {file_name}")
        return
    
    try:
        # Download file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        file_content = blob.download_as_bytes()
        
        # Process with Document AI
        processor_name = f"projects/{os.environ.get('GCP_PROJECT')}/locations/{os.environ.get('FUNCTION_REGION')}/processors/{os.environ.get('PROCESSOR_ID')}"
        docai_results = process_document_ai(file_content, processor_name)
        
        # Validate with Gemini
        gemini_analysis = validate_with_gemini(docai_results)
        
        # Combine results
        final_results = {
            "source_file": file_name,
            "timestamp": cloud_event.data.get('timeCreated'),
            "document_ai_extraction": docai_results,
            "gemini_analysis": gemini_analysis,
            "processing_complete": True
        }
        
        # Save results to output bucket
        output_bucket = storage_client.bucket(os.environ.get('OUTPUT_BUCKET'))
        output_file = f"processed/{file_name.replace('.pdf', '_results.json')}"
        output_blob = output_bucket.blob(output_file)
        output_blob.upload_from_string(
            json.dumps(final_results, indent=2),
            content_type='application/json'
        )
        
        print(f"Successfully processed {file_name} -> {output_file}")
        
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise
EOT
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"

  depends_on = [
    local_file.function_requirements,
    local_file.function_main
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function_source/${random_id.suffix.hex}/source.zip"
  bucket = google_storage_bucket.output_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# ================================
# Cloud Function
# ================================

# Cloud Function for form processing with storage trigger
resource "google_cloudfunctions2_function" "form_processor" {
  name     = local.function_name
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = "process_form"

    source {
      storage_source {
        bucket = google_storage_bucket.output_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"

    environment_variables = {
      GCP_PROJECT      = var.project_id
      FUNCTION_REGION  = var.region
      PROCESSOR_ID     = google_document_ai_processor.form_parser.name
      OUTPUT_BUCKET    = google_storage_bucket.output_bucket.name
      VERTEX_AI_MODEL  = var.vertex_ai_model
    }

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"

    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_documentai_user,
    google_project_iam_member.function_aiplatform_user,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_logging_writer,
    google_project_iam_member.function_monitoring_writer
  ]
}

# ================================
# Monitoring and Logging
# ================================

# Log sink for Cloud Function logs (optional - for custom log routing)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_function_logging ? 1 : 0

  name                   = "${local.name_prefix}-function-logs"
  description           = "Log sink for smart form processing function"
  destination           = "storage.googleapis.com/${google_storage_bucket.output_bucket.name}"
  filter                = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
  unique_writer_identity = true

  depends_on = [google_cloudfunctions2_function.form_processor]
}

# Grant the log sink writer access to the output bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_function_logging ? 1 : 0

  bucket = google_storage_bucket.output_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}