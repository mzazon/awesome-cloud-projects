# Outputs for Automated Threat Response Infrastructure
# This file defines outputs that provide important information about deployed resources

# Project and Deployment Information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for this infrastructure"
  value       = local.resource_suffix
}

output "deployment_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Pub/Sub Infrastructure Outputs
output "pubsub_topics" {
  description = "Information about created Pub/Sub topics"
  value = {
    main_topic = {
      name = google_pubsub_topic.threat_response_main.name
      id   = google_pubsub_topic.threat_response_main.id
    }
    remediation_topic = {
      name = google_pubsub_topic.threat_remediation.name
      id   = google_pubsub_topic.threat_remediation.id
    }
    notification_topic = {
      name = google_pubsub_topic.threat_notification.name
      id   = google_pubsub_topic.threat_notification.id
    }
    dead_letter_topic = {
      name = google_pubsub_topic.dead_letter.name
      id   = google_pubsub_topic.dead_letter.id
    }
  }
}

output "pubsub_subscriptions" {
  description = "Information about created Pub/Sub subscriptions"
  value = {
    main_subscription = {
      name = google_pubsub_subscription.threat_response_main.name
      id   = google_pubsub_subscription.threat_response_main.id
    }
    remediation_subscription = {
      name = google_pubsub_subscription.threat_remediation.name
      id   = google_pubsub_subscription.threat_remediation.id
    }
    notification_subscription = {
      name = google_pubsub_subscription.threat_notification.name
      id   = google_pubsub_subscription.threat_notification.id
    }
  }
}

# Cloud Functions Outputs
output "cloud_functions" {
  description = "Information about deployed Cloud Functions"
  value = {
    security_triage = {
      name         = google_cloudfunctions_function.security_triage.name
      trigger_type = "pubsub"
      trigger_topic = google_pubsub_topic.threat_response_main.name
      runtime      = google_cloudfunctions_function.security_triage.runtime
      memory_mb    = google_cloudfunctions_function.security_triage.available_memory_mb
      timeout      = google_cloudfunctions_function.security_triage.timeout
    }
    automated_remediation = {
      name         = google_cloudfunctions_function.automated_remediation.name
      trigger_type = "pubsub"
      trigger_topic = google_pubsub_topic.threat_remediation.name
      runtime      = google_cloudfunctions_function.automated_remediation.runtime
      memory_mb    = google_cloudfunctions_function.automated_remediation.available_memory_mb
      timeout      = google_cloudfunctions_function.automated_remediation.timeout
    }
    security_notification = {
      name         = google_cloudfunctions_function.security_notification.name
      trigger_type = "pubsub"
      trigger_topic = google_pubsub_topic.threat_notification.name
      runtime      = google_cloudfunctions_function.security_notification.runtime
      memory_mb    = google_cloudfunctions_function.security_notification.available_memory_mb
      timeout      = google_cloudfunctions_function.security_notification.timeout
    }
  }
}

output "function_urls" {
  description = "Cloud Function trigger URLs (for HTTPS triggered functions)"
  value = {
    security_triage       = "gs://${google_cloudfunctions_function.security_triage.source_archive_bucket}/${google_cloudfunctions_function.security_triage.source_archive_object}"
    automated_remediation = "gs://${google_cloudfunctions_function.automated_remediation.source_archive_bucket}/${google_cloudfunctions_function.automated_remediation.source_archive_object}"
    security_notification = "gs://${google_cloudfunctions_function.security_notification.source_archive_bucket}/${google_cloudfunctions_function.security_notification.source_archive_object}"
  }
}

# Service Account Outputs
output "service_accounts" {
  description = "Information about created service accounts"
  value = var.create_service_accounts ? {
    triage_function = {
      email      = google_service_account.triage_function[0].email
      account_id = google_service_account.triage_function[0].account_id
    }
    remediation_function = {
      email      = google_service_account.remediation_function[0].email
      account_id = google_service_account.remediation_function[0].account_id
    }
    notification_function = {
      email      = google_service_account.notification_function[0].email
      account_id = google_service_account.notification_function[0].account_id
    }
  } : {}
}

# Logging Infrastructure Outputs
output "logging_sink" {
  description = "Information about the Cloud Logging sink"
  value = {
    name               = google_logging_project_sink.security_findings.name
    destination        = google_logging_project_sink.security_findings.destination
    filter            = google_logging_project_sink.security_findings.filter
    writer_identity   = google_logging_project_sink.security_findings.writer_identity
  }
}

# Storage Outputs
output "function_source_bucket" {
  description = "Cloud Storage bucket used for function source code"
  value = var.create_source_bucket ? {
    name     = google_storage_bucket.function_source[0].name
    url      = google_storage_bucket.function_source[0].url
    location = google_storage_bucket.function_source[0].location
  } : {
    name = var.function_source_archive_bucket
  }
}

# Monitoring Outputs
output "monitoring_resources" {
  description = "Information about monitoring and alerting resources"
  value = var.enable_monitoring_alerts ? {
    custom_metrics = {
      security_findings_processed = google_monitoring_metric_descriptor.security_findings_processed[0].type
    }
    alert_policies = {
      critical_findings = {
        name = google_monitoring_alert_policy.critical_security_findings[0].name
        id   = google_monitoring_alert_policy.critical_security_findings[0].name
      }
      function_errors = {
        name = google_monitoring_alert_policy.function_errors[0].name
        id   = google_monitoring_alert_policy.function_errors[0].name
      }
    }
  } : {}
}

# Security Configuration Outputs
output "security_configuration" {
  description = "Security-related configuration information"
  value = {
    log_filter                    = var.security_findings_log_filter
    enable_security_command_center = var.enable_security_command_center
    enable_audit_logging         = var.enable_audit_logging
    log_retention_days           = var.log_retention_days
  }
}

# Testing and Validation Outputs
output "testing_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    list_functions = "gcloud functions list --filter=\"name:security\" --format=\"table(name,status,trigger.eventTrigger.eventType)\""
    list_topics    = "gcloud pubsub topics list --format=\"table(name)\""
    list_subscriptions = "gcloud pubsub subscriptions list --format=\"table(name,topic)\""
    test_message_publish = "gcloud pubsub topics publish ${google_pubsub_topic.threat_response_main.name} --message='{\"name\":\"test-finding\",\"severity\":\"HIGH\",\"category\":\"TEST\"}'"
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions_function.security_triage.name} --limit=10"
  }
}

# Integration Endpoints
output "integration_endpoints" {
  description = "Endpoints and identifiers for external integrations"
  value = {
    pubsub_topic_for_external_publishers = google_pubsub_topic.threat_response_main.id
    project_number = data.google_project.current.number
    log_sink_service_account = google_logging_project_sink.security_findings.writer_identity
  }
}

# Data source to get project information
data "google_project" "current" {
  project_id = var.project_id
}

# Resource Summary for Quick Reference
output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    total_functions     = 3
    total_topics       = 4 # Including dead letter topic
    total_subscriptions = 3
    total_service_accounts = var.create_service_accounts ? 3 : 0
    total_alert_policies = var.enable_monitoring_alerts ? 2 : 0
    deployment_cost_estimate = "Estimated monthly cost: $20-40 USD (varies by usage)"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up deployed resources"
  value = {
    delete_functions = "gcloud functions delete ${google_cloudfunctions_function.security_triage.name} ${google_cloudfunctions_function.automated_remediation.name} ${google_cloudfunctions_function.security_notification.name} --quiet"
    delete_topics    = "gcloud pubsub topics delete ${google_pubsub_topic.threat_response_main.name} ${google_pubsub_topic.threat_remediation.name} ${google_pubsub_topic.threat_notification.name} ${google_pubsub_topic.dead_letter.name} --quiet"
    delete_sink      = "gcloud logging sinks delete ${google_logging_project_sink.security_findings.name} --quiet"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# Configuration Validation Outputs
output "configuration_warnings" {
  description = "Important configuration notes and warnings"
  value = {
    security_command_center_note = "Security Command Center Premium or Enterprise is required for advanced threat detection features"
    service_account_note = var.create_service_accounts ? "Dedicated service accounts created with least privilege access" : "Using default Compute Engine service account - consider creating dedicated service accounts"
    monitoring_note = var.enable_monitoring_alerts ? "Monitoring alerts enabled - configure notification channels for proper alerting" : "Monitoring alerts disabled - enable for production deployments"
    external_integrations_note = var.enable_external_integrations ? "External integrations enabled - ensure secrets are properly configured" : "External integrations disabled"
  }
}