# Main Terraform configuration for Legal Document Analysis with Gemini Fine-Tuning
# This file creates the complete infrastructure for automated legal document processing

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = "legal-document-analysis"
  })

  # Resource naming with prefix and suffix
  name_prefix = "${var.resource_prefix}-${var.environment}"
  name_suffix = random_id.suffix.hex

  # Bucket names (must be globally unique)
  bucket_docs     = "${local.name_prefix}-docs-${local.name_suffix}"
  bucket_training = "${local.name_prefix}-training-${local.name_suffix}"
  bucket_results  = "${local.name_prefix}-results-${local.name_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "documentai.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# Cloud Storage bucket for legal documents (input)
resource "google_storage_bucket" "legal_documents" {
  name     = local.bucket_docs
  location = var.region
  project  = var.project_id

  # Enable versioning for document protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Security settings
  uniform_bucket_level_access = true

  # Enable public access prevention
  public_access_prevention = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for training data
resource "google_storage_bucket" "training_data" {
  name     = local.bucket_training
  location = var.region
  project  = var.project_id

  # Enable versioning for training data protection
  versioning {
    enabled = var.enable_versioning
  }

  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for analysis results
resource "google_storage_bucket" "analysis_results" {
  name     = local.bucket_results
  location = var.region
  project  = var.project_id

  # Enable versioning for results protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for results
  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload sample training data for legal document analysis
resource "google_storage_bucket_object" "training_data" {
  name   = "legal_training_examples.jsonl"
  bucket = google_storage_bucket.training_data.name
  content = jsonencode({
    messages = [
      {
        role    = "user"
        content = "Analyze this legal clause: WHEREAS, the Company desires to engage the Consultant to provide certain consulting services; and WHEREAS, the Consultant agrees to provide such services subject to the terms and conditions set forth herein;"
      },
      {
        role    = "assistant"
        content = "CONTRACT_TYPE: Consulting Agreement\nPARTIES: Company (Client), Consultant (Service Provider)\nKEY_CLAUSES: Service provision clause, Terms and conditions reference\nCOMPLIANCE_NOTES: Standard recital language establishing intent and agreement"
      }
    ]
  })

  depends_on = [google_storage_bucket.training_data]
}

# Document AI processor for legal document processing
resource "google_document_ai_processor" "legal_processor" {
  location     = var.region
  display_name = "Legal Document Processor"
  type         = var.document_ai_processor_type
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${local.name_prefix}-func-sa-${local.name_suffix}"
  display_name = "Legal Document Analysis Function Service Account"
  description  = "Service account for legal document processing Cloud Functions"
  project      = var.project_id
}

# IAM bindings for function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator",
    "roles/documentai.apiUser",
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create ZIP archive for document processor function
data "archive_file" "processor_function_zip" {
  type        = "zip"
  output_path = "/tmp/processor_function.zip"
  source {
    content = <<EOF
import json
import base64
from google.cloud import documentai_v1 as documentai
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
import os

# Initialize clients
doc_client = documentai.DocumentProcessorServiceClient()
storage_client = storage.Client()

def process_document_with_ai(document_content, processor_name):
    """Process document using Document AI"""
    raw_document = documentai.RawDocument(
        content=document_content,
        mime_type="application/pdf"
    )
    
    request = documentai.ProcessRequest(
        name=processor_name,
        raw_document=raw_document
    )
    
    result = doc_client.process_document(request=request)
    return result.document

def analyze_with_tuned_gemini(text_content, project_id, region):
    """Analyze extracted text with fine-tuned Gemini model"""
    try:
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)
        
        # Create prediction request for fine-tuned model
        prompt = f"""Analyze the following legal document text and provide structured analysis:
        
        Document Text:
        {text_content}
        
        Please provide analysis in the following format:
        CONTRACT_TYPE: [Type of legal document]
        KEY_CLAUSES: [Important clauses identified]
        PARTIES: [Parties involved]
        OBLIGATIONS: [Key obligations and responsibilities]
        RISKS: [Potential legal risks or concerns]
        COMPLIANCE_NOTES: [Compliance considerations]
        """
        
        # For this demo, we'll use a simulated analysis
        # In production, this would call the actual fine-tuned model endpoint
        analysis = {
            "contract_type": "Legal Document",
            "key_clauses": "Extracted key provisions from document",
            "parties": "Document parties identified from text",
            "obligations": "Key responsibilities and obligations outlined",
            "risks": "Potential compliance concerns identified",
            "compliance_status": "Requires legal review for accuracy",
            "confidence_score": 0.85,
            "analysis_timestamp": "2025-01-16T00:00:00Z"
        }
        
        return analysis
        
    except Exception as e:
        print(f"Error in analysis: {str(e)}")
        return {
            "error": str(e),
            "status": "analysis_failed",
            "confidence_score": 0.0
        }

@functions_framework.cloud_event
def legal_document_processor(cloud_event):
    """Main function triggered by Cloud Storage events"""
    project_id = os.environ.get('PROJECT_ID')
    region = os.environ.get('REGION')
    processor_name = os.environ.get('PROCESSOR_ID')
    results_bucket_name = os.environ.get('RESULTS_BUCKET')
    
    # Extract file information from event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing document: {file_name} from bucket: {bucket_name}")
    
    try:
        # Download document from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        document_content = blob.download_as_bytes()
        
        # Process with Document AI
        document = process_document_with_ai(document_content, processor_name)
        
        # Extract text content
        text_content = document.text
        
        # Analyze with fine-tuned Gemini (or simulated analysis)
        analysis = analyze_with_tuned_gemini(text_content, project_id, region)
        
        # Save analysis results
        results_bucket = storage_client.bucket(results_bucket_name)
        result_blob = results_bucket.blob(f"analysis_{file_name}.json")
        
        analysis_result = {
            "document_name": file_name,
            "bucket_name": bucket_name,
            "extracted_text": text_content[:2000] if text_content else "No text extracted",
            "analysis": analysis,
            "processing_timestamp": cloud_event.timestamp,
            "document_confidence": getattr(document, 'confidence', 0.9),
            "processor_used": processor_name.split('/')[-1],
            "status": "completed"
        }
        
        result_blob.upload_from_string(
            json.dumps(analysis_result, indent=2),
            content_type='application/json'
        )
        
        print(f"✅ Analysis completed for {file_name}")
        print(f"Results saved to: analysis_{file_name}.json")
        
    except Exception as e:
        print(f"❌ Error processing {file_name}: {str(e)}")
        
        # Save error information for debugging
        error_result = {
            "document_name": file_name,
            "bucket_name": bucket_name,
            "error": str(e),
            "processing_timestamp": cloud_event.timestamp,
            "status": "failed"
        }
        
        try:
            results_bucket = storage_client.bucket(results_bucket_name)
            error_blob = results_bucket.blob(f"error_{file_name}.json")
            error_blob.upload_from_string(
                json.dumps(error_result, indent=2),
                content_type='application/json'
            )
        except Exception as save_error:
            print(f"Failed to save error information: {str(save_error)}")
        
        raise
EOF
    filename = "main.py"
  }
  source {
    content  = "google-cloud-documentai==2.21.0\ngoogle-cloud-aiplatform==1.40.0\ngoogle-cloud-storage==2.10.0\nfunctions-framework==3.5.0"
    filename = "requirements.txt"
  }
}

# Upload function code to Cloud Storage
resource "google_storage_bucket_object" "processor_function_source" {
  name   = "processor_function_${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.analysis_results.name
  source = data.archive_file.processor_function_zip.output_path

  depends_on = [data.archive_file.processor_function_zip]
}

# Cloud Function for document processing
resource "google_cloudfunctions2_function" "document_processor" {
  name     = "${local.name_prefix}-processor-${local.name_suffix}"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python39"
    entry_point = "legal_document_processor"
    
    source {
      storage_source {
        bucket = google_storage_bucket.analysis_results.name
        object = google_storage_bucket_object.processor_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      REGION           = var.region
      PROCESSOR_ID     = google_document_ai_processor.legal_processor.name
      RESULTS_BUCKET   = google_storage_bucket.analysis_results.name
      TRAINING_BUCKET  = google_storage_bucket.training_data.name
    }

    service_account_email = google_service_account.function_sa.email
  }

  # Event trigger for Cloud Storage uploads
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.legal_documents.name
    }

    service_account_email = google_service_account.function_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles,
    google_storage_bucket_object.processor_function_source
  ]
}

# Create ZIP archive for dashboard function
data "archive_file" "dashboard_function_zip" {
  type        = "zip"
  output_path = "/tmp/dashboard_function.zip"
  source {
    content = <<EOF
import json
import os
from google.cloud import storage
from datetime import datetime
import functions_framework

@functions_framework.http
def generate_legal_dashboard(request):
    """Generate legal analysis dashboard from processed documents"""
    
    try:
        # Initialize storage client
        storage_client = storage.Client()
        results_bucket_name = os.environ.get('RESULTS_BUCKET')
        results_bucket = storage_client.bucket(results_bucket_name)
        
        # Get all analysis results
        analyses = []
        errors = []
        
        for blob in results_bucket.list_blobs():
            if blob.name.startswith("analysis_"):
                try:
                    content = blob.download_as_text()
                    analysis = json.loads(content)
                    analyses.append(analysis)
                except Exception as e:
                    print(f"Error processing analysis file {blob.name}: {str(e)}")
            elif blob.name.startswith("error_"):
                try:
                    content = blob.download_as_text()
                    error = json.loads(content)
                    errors.append(error)
                except Exception as e:
                    print(f"Error processing error file {blob.name}: {str(e)}")
        
        # Generate dashboard HTML with improved styling
        dashboard_html = f'''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Legal Document Analysis Dashboard</title>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }}
                .container {{ max-width: 1200px; margin: 0 auto; }}
                .header {{ background: linear-gradient(135deg, #1a73e8, #34a853); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }}
                .header h1 {{ margin: 0 0 10px 0; font-size: 2.5em; }}
                .header p {{ margin: 5px 0; opacity: 0.9; }}
                .metrics {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }}
                .metric-card {{ background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }}
                .metric-value {{ font-size: 2.5em; font-weight: bold; color: #1a73e8; margin-bottom: 5px; }}
                .metric-label {{ color: #666; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }}
                .analysis {{ background: white; border: 1px solid #e0e0e0; margin: 10px 0; padding: 20px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
                .analysis h3 {{ margin-top: 0; color: #1a73e8; border-bottom: 2px solid #f0f0f0; padding-bottom: 10px; }}
                .confidence {{ color: #34a853; font-weight: bold; background: #e8f5e8; padding: 5px 10px; border-radius: 20px; display: inline-block; }}
                .analysis-content {{ background: #f8f9fa; padding: 15px; border-radius: 5px; margin: 10px 0; font-family: 'Courier New', monospace; font-size: 0.9em; }}
                .text-preview {{ background: #f5f5f5; padding: 15px; border-radius: 5px; max-height: 200px; overflow-y: auto; font-size: 0.85em; line-height: 1.4; border: 1px solid #ddd; }}
                .recommendations {{ background: white; padding: 25px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-top: 20px; }}
                .recommendations h2 {{ color: #1a73e8; margin-top: 0; }}
                .recommendations ul {{ list-style-type: none; padding: 0; }}
                .recommendations li {{ background: #f8f9fa; margin: 10px 0; padding: 15px; border-radius: 5px; border-left: 4px solid #1a73e8; }}
                .error-section {{ background: #fde7e7; border: 1px solid #f5c6cb; border-radius: 10px; padding: 20px; margin-bottom: 20px; }}
                .error-item {{ background: white; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #d93025; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>📄 Legal Document Analysis Dashboard</h1>
                    <p>🤖 Powered by Gemini Fine-Tuning and Document AI</p>
                    <p>📅 Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}</p>
                </div>
                
                <div class="metrics">
                    <div class="metric-card">
                        <div class="metric-value">{len(analyses) + len(errors)}</div>
                        <div class="metric-label">Documents Processed</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">{len(analyses)}</div>
                        <div class="metric-label">Successful Analyses</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">{len(errors)}</div>
                        <div class="metric-label">Processing Errors</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">{round(sum([a.get('document_confidence', 0.8) for a in analyses]) / max(len(analyses), 1) * 100, 1) if analyses else 0}%</div>
                        <div class="metric-label">Average Confidence</div>
                    </div>
                </div>
        '''
        
        # Add errors section if any
        if errors:
            dashboard_html += '<div class="error-section"><h2>⚠️ Processing Errors</h2>'
            for error in errors:
                dashboard_html += f'''
                <div class="error-item">
                    <h4>{error.get('document_name', 'Unknown')}</h4>
                    <p><strong>Error:</strong> {error.get('error', 'Unknown error')}</p>
                    <p><strong>Time:</strong> {error.get('processing_timestamp', 'Unknown')}</p>
                </div>
                '''
            dashboard_html += '</div>'
        
        # Add analysis results
        if analyses:
            dashboard_html += '<h2>📋 Document Analysis Results</h2>'
            for analysis in analyses:
                dashboard_html += f'''
                <div class="analysis">
                    <h3>📄 {analysis.get('document_name', 'Unknown Document')}</h3>
                    <p><strong>⏰ Processed:</strong> {analysis.get('processing_timestamp', 'Unknown')}</p>
                    <p><strong>🏢 Source Bucket:</strong> {analysis.get('bucket_name', 'Unknown')}</p>
                    <div class="confidence">
                        🎯 Confidence: {round(analysis.get('document_confidence', 0.8) * 100)}%
                    </div>
                    
                    <p><strong>🔍 Analysis Results:</strong></p>
                    <div class="analysis-content">
                '''
                
                analysis_data = analysis.get('analysis', {})
                if analysis_data.get('contract_type'):
                    dashboard_html += f"<strong>📝 Contract Type:</strong> {analysis_data['contract_type']}<br>"
                if analysis_data.get('key_clauses'):
                    dashboard_html += f"<strong>🔑 Key Clauses:</strong> {analysis_data['key_clauses']}<br>"
                if analysis_data.get('parties'):
                    dashboard_html += f"<strong>👥 Parties:</strong> {analysis_data['parties']}<br>"
                if analysis_data.get('obligations'):
                    dashboard_html += f"<strong>📋 Obligations:</strong> {analysis_data['obligations']}<br>"
                if analysis_data.get('risks'):
                    dashboard_html += f"<strong>⚠️ Risks:</strong> {analysis_data['risks']}<br>"
                if analysis_data.get('compliance_status'):
                    dashboard_html += f"<strong>✅ Compliance:</strong> {analysis_data['compliance_status']}"
                
                dashboard_html += '</div>'
                
                if analysis.get('extracted_text'):
                    text_preview = analysis['extracted_text'][:1990] + ('...' if len(analysis['extracted_text']) > 1990 else '')
                    dashboard_html += f'''
                    <p><strong>📄 Document Text Preview:</strong></p>
                    <div class="text-preview">{text_preview}</div>
                    '''
                
                dashboard_html += '</div>'
        else:
            dashboard_html += '''
            <div class="analysis">
                <h3>📭 No Analysis Results Found</h3>
                <p>Upload legal documents to the processing bucket to see analysis results here.</p>
            </div>
            '''
        
        # Add recommendations section
        dashboard_html += '''
                <div class="recommendations">
                    <h2>💡 Recommendations</h2>
                    <ul>
                        <li>🔍 Review documents marked as high priority for immediate attention</li>
                        <li>⚖️ Address compliance issues identified in the analysis reports</li>
                        <li>👨‍💼 Schedule legal review for complex contract terms and unusual clauses</li>
                        <li>📋 Update document templates based on identified risk patterns</li>
                        <li>🎯 Monitor confidence scores and consider model retraining if scores drop below 80%</li>
                        <li>📊 Use analysis trends to improve document standardization processes</li>
                    </ul>
                </div>
                
                <div style="text-align: center; margin-top: 30px; color: #666; font-size: 0.9em;">
                    <p>⚡ Powered by Google Cloud AI • 🔒 Secure Document Processing • 📈 Automated Legal Analysis</p>
                </div>
            </div>
        </body>
        </html>
        '''
        
        # Save dashboard to results bucket
        dashboard_blob = results_bucket.blob("legal_dashboard.html")
        dashboard_blob.upload_from_string(
            dashboard_html, 
            content_type='text/html'
        )
        
        return {
            'status': 'success',
            'message': f'Dashboard generated with {len(analyses)} successful analyses and {len(errors)} errors',
            'dashboard_path': f'gs://{results_bucket_name}/legal_dashboard.html',
            'metrics': {
                'total_documents': len(analyses) + len(errors),
                'successful_analyses': len(analyses),
                'errors': len(errors),
                'avg_confidence': f'{round(sum([a.get("document_confidence", 0.8) for a in analyses]) / max(len(analyses), 1) * 100, 1) if analyses else 0}%'
            }
        }, 200
        
    except Exception as e:
        error_message = f"Error generating dashboard: {str(e)}"
        print(error_message)
        return {
            'status': 'error', 
            'message': error_message
        }, 500
EOF
    filename = "main.py"
  }
  source {
    content  = "google-cloud-storage==2.10.0\nfunctions-framework==3.5.0"
    filename = "requirements.txt"
  }
}

# Upload dashboard function code to Cloud Storage
resource "google_storage_bucket_object" "dashboard_function_source" {
  name   = "dashboard_function_${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.analysis_results.name
  source = data.archive_file.dashboard_function_zip.output_path

  depends_on = [data.archive_file.dashboard_function_zip]
}

# Cloud Function for dashboard generation
resource "google_cloudfunctions2_function" "dashboard_generator" {
  name     = "${local.name_prefix}-dashboard-${local.name_suffix}"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python39"
    entry_point = "generate_legal_dashboard"
    
    source {
      storage_source {
        bucket = google_storage_bucket.analysis_results.name
        object = google_storage_bucket_object.dashboard_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 5
    min_instance_count = 0
    available_memory   = "256M"
    timeout_seconds    = 60
    
    environment_variables = {
      RESULTS_BUCKET = google_storage_bucket.analysis_results.name
    }

    service_account_email = google_service_account.function_sa.email

    # Allow unauthenticated access if enabled (for demo purposes)
    ingress_settings = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles,
    google_storage_bucket_object.dashboard_function_source
  ]
}

# IAM policy to allow unauthenticated access to dashboard function (if enabled)
resource "google_cloud_run_service_iam_member" "dashboard_public_access" {
  count = var.enable_public_access ? 1 : 0

  location = google_cloudfunctions2_function.dashboard_generator.location
  project  = google_cloudfunctions2_function.dashboard_generator.project
  service  = google_cloudfunctions2_function.dashboard_generator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Monitoring alert policy for function errors (if monitoring enabled)
resource "google_monitoring_alert_policy" "function_error_alert" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  display_name = "Legal Document Analysis Function Errors"
  project      = var.project_id

  conditions {
    display_name = "Function error rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.document_processor.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Send notification to email if provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      channel_id = notification_channels.value
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_project_service.required_apis]
}

# Email notification channel for monitoring alerts
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  display_name = "Legal Analysis Email Notifications"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Log sink for function logs (optional - for advanced monitoring)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0

  name        = "${local.name_prefix}-function-logs-${local.name_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.analysis_results.name}"
  
  filter = "resource.type=\"cloud_function\" AND (resource.labels.function_name=\"${google_cloudfunctions2_function.document_processor.name}\" OR resource.labels.function_name=\"${google_cloudfunctions2_function.dashboard_generator.name}\")"

  # Grant the sink writer identity permission to write to the bucket
  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Grant log sink writer permission to write to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0

  bucket = google_storage_bucket.analysis_results.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}