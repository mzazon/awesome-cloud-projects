# Main Terraform configuration for Document Intelligence Workflows with Agentspace and Sensitive Data Protection
# This file creates a comprehensive document processing pipeline using Google Cloud AI services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct unique resource names
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
  })
  
  # Storage bucket names (must be globally unique)
  input_bucket_name  = "doc-input-${local.resource_suffix}"
  output_bucket_name = "doc-output-${local.resource_suffix}"
  audit_bucket_name  = "doc-audit-${local.resource_suffix}"
  
  # BigQuery dataset and table names
  dataset_name = "document_intelligence"
  table_name   = "processed_documents"
  
  # Service account email
  agentspace_sa_email = "agentspace-doc-processor@${var.project_id}.iam.gserviceaccount.com"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "dlp.googleapis.com",
    "workflows.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Document AI Processor for intelligent document analysis
resource "google_document_ai_processor" "enterprise_processor" {
  location     = var.region
  display_name = "${var.document_processor_display_name}-${local.resource_suffix}"
  type         = var.document_processor_type
  
  depends_on = [google_project_service.apis]
  
  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# Cloud Storage bucket for document input
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_bucket_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning for data protection
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage bucket for processed document output
resource "google_storage_bucket" "output_bucket" {
  name          = local.output_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_bucket_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning for data protection
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage bucket for audit logs and compliance tracking
resource "google_storage_bucket" "audit_bucket" {
  name          = local.audit_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security configurations for audit data
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_bucket_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning for audit trail integrity
  versioning {
    enabled = true
  }
  
  # Extended retention for compliance
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days > 0 ? var.bucket_lifecycle_age_days * 2 : 730
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "audit-compliance"
  })
  
  depends_on = [google_project_service.apis]
}

# DLP Inspection Template for comprehensive PII detection
resource "google_data_loss_prevention_inspect_template" "pii_scanner" {
  parent       = "projects/${var.project_id}"
  description  = "Comprehensive PII detection template for enterprise documents"
  display_name = "Enterprise Document PII Scanner"
  
  inspect_config {
    # Configure information types for detection
    dynamic "info_types" {
      for_each = var.dlp_info_types
      content {
        name = info_types.value
      }
    }
    
    min_likelihood = var.dlp_min_likelihood
    include_quote  = true
    
    limits {
      max_findings_per_request = var.dlp_max_findings_per_request
    }
    
    # Rule sets for enhanced detection accuracy
    rule_set {
      info_types {
        name = "EMAIL_ADDRESS"
      }
      rules {
        exclusion_rule {
          matching_type = "MATCHING_TYPE_FULL_MATCH"
          regex {
            pattern = ".*@(test|example|demo)\\.(com|org|net)"
          }
        }
      }
    }
  }
  
  depends_on = [google_project_service.apis]
}

# DLP De-identification Template for data redaction
resource "google_data_loss_prevention_deidentify_template" "data_redaction" {
  parent       = "projects/${var.project_id}"
  description  = "Automated redaction template for sensitive data in documents"
  display_name = "Enterprise Document Redaction"
  
  deidentify_config {
    info_type_transformations {
      # Standard redaction for common PII
      transformations {
        info_types {
          name = "EMAIL_ADDRESS"
        }
        info_types {
          name = "PERSON_NAME"
        }
        info_types {
          name = "PHONE_NUMBER"
        }
        
        primitive_transformation {
          replace_config {
            new_value {
              string_value = "[REDACTED]"
            }
          }
        }
      }
      
      # Cryptographic hashing for sensitive financial data
      transformations {
        info_types {
          name = "CREDIT_CARD_NUMBER"
        }
        info_types {
          name = "US_SOCIAL_SECURITY_NUMBER"
        }
        
        primitive_transformation {
          crypto_hash_config {
            crypto_key {
              unwrapped {
                key = base64encode("document-intelligence-key-32b")
              }
            }
          }
        }
      }
    }
  }
  
  depends_on = [google_project_service.apis]
}

# BigQuery dataset for document intelligence analytics
resource "google_bigquery_dataset" "document_intelligence" {
  dataset_id  = local.dataset_name
  location    = var.bigquery_dataset_location
  description = "Document intelligence processing analytics and compliance tracking"
  
  # Data retention and lifecycle
  dynamic "default_table_expiration_ms" {
    for_each = var.bigquery_table_expiration_days > 0 ? [1] : []
    content {
      default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# BigQuery table for processed document metadata
resource "google_bigquery_table" "processed_documents" {
  dataset_id = google_bigquery_dataset.document_intelligence.dataset_id
  table_id   = local.table_name
  
  description = "Metadata and analytics for processed documents"
  
  schema = jsonencode([
    {
      name = "document_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the processed document"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when document processing was completed"
    },
    {
      name = "document_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Classified type of the document"
    },
    {
      name = "sensitive_data_found"
      type = "BOOLEAN"
      mode = "REQUIRED"
      description = "Whether sensitive data was detected in the document"
    },
    {
      name = "compliance_level"
      type = "STRING"
      mode = "REQUIRED"
      description = "Compliance level classification (low, medium, high)"
    },
    {
      name = "processing_status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Final processing status (completed, failed, partial)"
    },
    {
      name = "file_path"
      type = "STRING"
      mode = "REQUIRED"
      description = "Storage path of the processed document"
    },
    {
      name = "entities_extracted"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of entities extracted from the document"
    },
    {
      name = "redaction_applied"
      type = "BOOLEAN"
      mode = "REQUIRED"
      description = "Whether redaction was applied to the document"
    }
  ])
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.document_intelligence]
}

# BigQuery view for compliance reporting
resource "google_bigquery_table" "compliance_summary" {
  dataset_id = google_bigquery_dataset.document_intelligence.dataset_id
  table_id   = "compliance_summary"
  
  description = "Aggregated compliance summary view for document processing"
  
  view {
    query = <<-EOF
      SELECT 
        DATE(processing_timestamp) as processing_date,
        document_type,
        compliance_level,
        COUNT(*) as document_count,
        SUM(CASE WHEN sensitive_data_found THEN 1 ELSE 0 END) as sensitive_documents,
        SUM(CASE WHEN redaction_applied THEN 1 ELSE 0 END) as redacted_documents,
        ROUND(SUM(CASE WHEN sensitive_data_found THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) as sensitive_data_percentage
      FROM `${var.project_id}.${local.dataset_name}.${local.table_name}`
      GROUP BY processing_date, document_type, compliance_level
      ORDER BY processing_date DESC, document_count DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.processed_documents]
}

# Service account for Agentspace integration
resource "google_service_account" "agentspace_processor" {
  account_id   = "agentspace-doc-processor"
  display_name = var.agentspace_service_account_display_name
  description  = var.agentspace_service_account_description
  
  depends_on = [google_project_service.apis]
}

# IAM roles for Agentspace service account
resource "google_project_iam_member" "agentspace_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.agentspace_processor.email}"
}

resource "google_project_iam_member" "agentspace_dlp_user" {
  project = var.project_id
  role    = "roles/dlp.user"
  member  = "serviceAccount:${google_service_account.agentspace_processor.email}"
}

resource "google_project_iam_member" "agentspace_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.agentspace_processor.email}"
}

resource "google_project_iam_member" "agentspace_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.agentspace_processor.email}"
}

resource "google_project_iam_member" "agentspace_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.agentspace_processor.email}"
}

# Cloud Workflows for document processing orchestration
resource "google_workflows_workflow" "document_processing" {
  name            = "doc-intelligence-workflow-${local.resource_suffix}"
  region          = var.region
  description     = "Orchestrates document processing through Document AI, DLP, and Agentspace"
  service_account = google_service_account.agentspace_processor.email
  
  source_contents = templatefile("${path.module}/workflow.yaml.tpl", {
    project_id               = var.project_id
    region                  = var.region
    processor_name          = google_document_ai_processor.enterprise_processor.name
    input_bucket            = google_storage_bucket.input_bucket.name
    output_bucket           = google_storage_bucket.output_bucket.name
    audit_bucket            = google_storage_bucket.audit_bucket.name
    dlp_inspect_template    = google_data_loss_prevention_inspect_template.pii_scanner.name
    dlp_deidentify_template = google_data_loss_prevention_deidentify_template.data_redaction.name
    bigquery_dataset        = google_bigquery_dataset.document_intelligence.dataset_id
    bigquery_table          = google_bigquery_table.processed_documents.table_id
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.agentspace_processor,
    google_document_ai_processor.enterprise_processor,
    google_data_loss_prevention_inspect_template.pii_scanner,
    google_data_loss_prevention_deidentify_template.data_redaction
  ]
}

# Workflow template file creation
resource "local_file" "workflow_template" {
  filename = "${path.module}/workflow.yaml.tpl"
  content = <<-EOF
main:
  params: [input]
  steps:
    - init:
        assign:
          - project_id: "${project_id}"
          - location: "${region}"
          - processor_name: "${processor_name}"
          - input_bucket: "${input_bucket}"
          - output_bucket: "${output_bucket}"
          - audit_bucket: "${audit_bucket}"
          - dlp_inspect_template: "${dlp_inspect_template}"
          - dlp_deidentify_template: "${dlp_deidentify_template}"
          - bigquery_dataset: "${bigquery_dataset}"
          - bigquery_table: "${bigquery_table}"
          - document_path: $${input.document_path}
          - processing_start_time: $${sys.now()}
    
    - log_processing_start:
        call: sys.log
        args:
          text: $${"Starting document processing for: " + document_path}
          severity: "INFO"
    
    - process_document_ai:
        call: http.post
        args:
          url: $${"https://documentai.googleapis.com/v1/" + processor_name + ":process"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            rawDocument:
              content: $${input.document_content}
              mimeType: "application/pdf"
        result: docai_response
    
    - extract_document_text:
        assign:
          - extracted_text: $${docai_response.body.document.text}
          - entities: $${docai_response.body.document.entities}
    
    - scan_for_sensitive_data:
        call: http.post
        args:
          url: $${"https://dlp.googleapis.com/v2/" + dlp_inspect_template + ":inspect"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            item:
              value: $${extracted_text}
        result: dlp_scan_response
    
    - evaluate_sensitivity:
        switch:
          - condition: $${len(dlp_scan_response.body.result.findings) > 0}
            next: redact_sensitive_data
          - condition: true
            next: store_clean_document
    
    - redact_sensitive_data:
        call: http.post
        args:
          url: $${"https://dlp.googleapis.com/v2/" + dlp_deidentify_template + ":deidentify"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            item:
              value: $${extracted_text}
        result: redaction_response
        next: store_redacted_document
    
    - store_redacted_document:
        assign:
          - redacted_content: $${redaction_response.body.item.value}
          - output_path: $${"gs://" + output_bucket + "/redacted/" + document_path}
          - redaction_applied: true
        next: insert_bigquery_record
    
    - store_clean_document:
        assign:
          - clean_content: $${extracted_text}
          - output_path: $${"gs://" + output_bucket + "/clean/" + document_path}
          - redaction_applied: false
        next: insert_bigquery_record
    
    - insert_bigquery_record:
        call: http.post
        args:
          url: $${"https://bigquery.googleapis.com/bigquery/v2/projects/" + project_id + "/datasets/" + bigquery_dataset + "/tables/" + bigquery_table + "/insertAll"}
          auth:
            type: OAuth2
          headers:
            Content-Type: "application/json"
          body:
            rows:
              - json:
                  document_id: $${document_path}
                  processing_timestamp: $${processing_start_time}
                  document_type: "general"
                  sensitive_data_found: $${len(dlp_scan_response.body.result.findings) > 0}
                  compliance_level: $${if(len(dlp_scan_response.body.result.findings) > 5, "high", if(len(dlp_scan_response.body.result.findings) > 0, "medium", "low"))}
                  processing_status: "completed"
                  file_path: $${output_path}
                  entities_extracted: $${len(entities)}
                  redaction_applied: $${redaction_applied}
        next: log_completion
    
    - log_completion:
        call: sys.log
        args:
          text: $${"Document processing completed for: " + document_path + " stored at: " + output_path}
          severity: "INFO"
        next: return_result
    
    - return_result:
        return:
          status: "completed"
          input_document: $${document_path}
          output_location: $${output_path}
          sensitive_data_found: $${len(dlp_scan_response.body.result.findings)}
          processing_time: $${sys.now() - processing_start_time}
          entities_extracted: $${len(entities)}
          redaction_applied: $${redaction_applied}
EOF
}

# Logging sink for audit trail
resource "google_logging_project_sink" "audit_sink" {
  name        = "doc-intelligence-audit-sink-${local.resource_suffix}"
  description = "Audit sink for document intelligence pipeline"
  
  destination = "storage.googleapis.com/${google_storage_bucket.audit_bucket.name}/audit-logs"
  
  filter = <<-EOF
    protoPayload.serviceName="documentai.googleapis.com" OR 
    protoPayload.serviceName="dlp.googleapis.com" OR
    protoPayload.serviceName="workflows.googleapis.com" OR
    protoPayload.serviceName="bigquery.googleapis.com"
  EOF
  
  unique_writer_identity = true
  
  depends_on = [google_storage_bucket.audit_bucket]
}

# Grant the logging sink permission to write to the audit bucket
resource "google_storage_bucket_iam_member" "audit_sink_writer" {
  bucket = google_storage_bucket.audit_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_sink.writer_identity
}

# Custom log-based metrics for monitoring
resource "google_logging_metric" "document_processing_volume" {
  name   = "document_processing_volume"
  filter = "resource.type=\"cloud_workflow\" AND jsonPayload.message:\"Document processing completed\""
  
  label_extractors = {
    "document_type" = "EXTRACT(jsonPayload.document_type)"
    "status"        = "EXTRACT(jsonPayload.status)"
  }
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Document Processing Volume"
    description  = "Volume of documents processed by the intelligence pipeline"
  }
  
  depends_on = [google_project_service.apis]
}

resource "google_logging_metric" "sensitive_data_detections" {
  name   = "sensitive_data_detections"
  filter = "resource.type=\"dlp_job\" AND jsonPayload.findings:*"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Sensitive Data Detections"
    description  = "Count of sensitive data detections in processed documents"
  }
  
  depends_on = [google_project_service.apis]
}

# Monitoring alert policy for high-risk document processing
resource "google_monitoring_alert_policy" "high_risk_processing" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "High-Risk Document Processing Alert"
  description  = "Alert when high volume of sensitive data is detected"
  
  conditions {
    display_name = "High sensitive data detection rate"
    
    condition_threshold {
      filter         = "metric.type=\"logging.googleapis.com/user/sensitive_data_detections\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  enabled = true
  
  depends_on = [
    google_project_service.apis,
    google_logging_metric.sensitive_data_detections
  ]
}