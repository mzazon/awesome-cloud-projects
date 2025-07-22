# Outputs for GCP compliance reporting infrastructure
# These outputs provide essential information for post-deployment configuration and integration

# ======================================
# PROJECT AND CONFIGURATION OUTPUTS
# ======================================

output "project_id" {
  description = "The GCP project ID where compliance infrastructure is deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "The unique suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ======================================
# STORAGE BUCKET OUTPUTS
# ======================================

output "audit_logs_bucket" {
  description = "Cloud Storage bucket for audit logs with compliance retention"
  value = {
    name     = google_storage_bucket.audit_logs.name
    url      = google_storage_bucket.audit_logs.url
    location = google_storage_bucket.audit_logs.location
  }
}

output "compliance_documents_bucket" {
  description = "Cloud Storage bucket for compliance documents and processing"
  value = {
    name     = google_storage_bucket.compliance_documents.name
    url      = google_storage_bucket.compliance_documents.url
    location = google_storage_bucket.compliance_documents.location
  }
}

output "compliance_reports_bucket" {
  description = "Cloud Storage bucket for generated compliance reports"
  value = {
    name     = google_storage_bucket.compliance_reports.name
    url      = google_storage_bucket.compliance_reports.url
    location = google_storage_bucket.compliance_reports.location
  }
}

# ======================================
# DOCUMENT AI PROCESSOR OUTPUTS
# ======================================

output "document_ai_processors" {
  description = "Document AI processors for compliance document analysis"
  value = {
    compliance_processor = {
      id           = google_document_ai_processor.compliance_processor.id
      name         = google_document_ai_processor.compliance_processor.name
      display_name = google_document_ai_processor.compliance_processor.display_name
      type         = google_document_ai_processor.compliance_processor.type
    }
    contract_processor = {
      id           = google_document_ai_processor.contract_processor.id
      name         = google_document_ai_processor.contract_processor.name
      display_name = google_document_ai_processor.contract_processor.display_name
      type         = google_document_ai_processor.contract_processor.type
    }
  }
}

# ======================================
# CLOUD FUNCTIONS OUTPUTS
# ======================================

output "cloud_functions" {
  description = "Cloud Functions for compliance processing workflows"
  value = {
    document_processor = {
      name = google_cloudfunctions2_function.document_processor.name
      uri  = google_cloudfunctions2_function.document_processor.service_config[0].uri
    }
    report_generator = {
      name = google_cloudfunctions2_function.report_generator.name
      uri  = google_cloudfunctions2_function.report_generator.service_config[0].uri
    }
    log_analytics = {
      name = google_cloudfunctions2_function.log_analytics.name
      uri  = google_cloudfunctions2_function.log_analytics.service_config[0].uri
    }
  }
}

# ======================================
# SERVICE ACCOUNT OUTPUTS
# ======================================

output "service_accounts" {
  description = "Service accounts created for compliance infrastructure"
  value = {
    compliance_functions = {
      email = google_service_account.compliance_function_sa.email
      name  = google_service_account.compliance_function_sa.name
    }
    scheduler = {
      email = google_service_account.scheduler_sa.email
      name  = google_service_account.scheduler_sa.name
    }
  }
}

# ======================================
# ENCRYPTION AND SECURITY OUTPUTS
# ======================================

output "kms_configuration" {
  description = "KMS encryption configuration for compliance data protection"
  value = {
    keyring = {
      name     = google_kms_key_ring.compliance_keyring.name
      location = google_kms_key_ring.compliance_keyring.location
    }
    crypto_key = {
      name = google_kms_crypto_key.compliance_key.name
      id   = google_kms_crypto_key.compliance_key.id
    }
  }
}

# ======================================
# AUDIT LOGGING OUTPUTS
# ======================================

output "audit_logging_configuration" {
  description = "Cloud Audit Logs configuration for compliance tracking"
  value = {
    log_sink = {
      name        = google_logging_project_sink.compliance_audit_sink.name
      destination = google_logging_project_sink.compliance_audit_sink.destination
      filter      = google_logging_project_sink.compliance_audit_sink.filter
      writer_identity = google_logging_project_sink.compliance_audit_sink.writer_identity
    }
    data_access_logs_enabled  = var.enable_data_access_logs
    admin_activity_logs_enabled = var.enable_admin_activity_logs
    retention_days = var.audit_log_retention_days
  }
}

# ======================================
# SCHEDULING AND AUTOMATION OUTPUTS
# ======================================

output "scheduled_jobs" {
  description = "Cloud Scheduler jobs for automated compliance operations"
  value = {
    compliance_reports = {
      name     = google_cloud_scheduler_job.compliance_report_job.name
      schedule = google_cloud_scheduler_job.compliance_report_job.schedule
    }
    compliance_analytics = {
      name     = google_cloud_scheduler_job.compliance_analytics_job.name
      schedule = google_cloud_scheduler_job.compliance_analytics_job.schedule
    }
  }
}

# ======================================
# MONITORING AND ALERTING OUTPUTS
# ======================================

output "monitoring_configuration" {
  description = "Monitoring and alerting configuration for compliance oversight"
  value = {
    log_metrics = {
      compliance_violations = google_logging_metric.compliance_violations.name
      document_processing_success = google_logging_metric.document_processing_success.name
    }
    notification_channels = {
      compliance_email = google_monitoring_notification_channel.compliance_email.name
    }
    alert_policies = {
      compliance_violations = google_monitoring_alert_policy.compliance_violation_alert.name
    }
  }
}

# ======================================
# COMPLIANCE FRAMEWORK OUTPUTS
# ======================================

output "compliance_configuration" {
  description = "Compliance framework configuration and settings"
  value = {
    supported_frameworks = var.compliance_frameworks
    notification_email   = var.notification_email
    report_schedule      = var.report_schedule
    analytics_schedule   = var.analytics_schedule
  }
}

# ======================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ======================================

output "deployment_verification" {
  description = "Commands and URLs for verifying the compliance infrastructure deployment"
  value = {
    test_document_upload = "gsutil cp test-document.pdf gs://${google_storage_bucket.compliance_documents.name}/policies/"
    trigger_manual_report = "gcloud functions call ${google_cloudfunctions2_function.report_generator.name} --region=${var.region} --data='{\"report_type\":\"manual\"}'"
    view_audit_logs = "gcloud logging read 'protoPayload.serviceName=\"storage.googleapis.com\"' --limit=10"
    check_scheduler_jobs = "gcloud scheduler jobs list --location=${var.region}"
  }
}

# ======================================
# COST OPTIMIZATION OUTPUTS
# ======================================

output "cost_optimization_info" {
  description = "Information about cost optimization features configured"
  value = {
    storage_lifecycle_enabled = true
    nearline_transition_days  = 30
    coldline_transition_days  = 90
    deletion_after_days      = var.audit_log_retention_days
    kms_key_rotation_period  = "90 days"
  }
}

# ======================================
# SECURITY FEATURES OUTPUTS
# ======================================

output "security_features" {
  description = "Security features and configurations implemented"
  value = {
    bucket_public_access_prevention = var.enable_public_access_prevention
    uniform_bucket_level_access    = var.enable_uniform_bucket_level_access
    object_versioning_enabled      = var.enable_versioning
    kms_encryption_enabled         = true
    audit_logging_comprehensive    = true
    iam_least_privilege           = true
  }
}

# ======================================
# NEXT STEPS OUTPUTS
# ======================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_upload_test_documents" = "Upload compliance documents to gs://${google_storage_bucket.compliance_documents.name}/policies/"
    "2_verify_processing"     = "Check processed documents in gs://${google_storage_bucket.compliance_documents.name}/processed/"
    "3_trigger_manual_report" = "Use the trigger_manual_report command from deployment_verification output"
    "4_review_audit_logs"     = "Monitor audit logs using Cloud Logging console or CLI commands"
    "5_configure_alerts"      = "Review and customize alert policies for your organization's needs"
    "6_schedule_testing"      = "Set up regular testing of the compliance pipeline"
  }
}