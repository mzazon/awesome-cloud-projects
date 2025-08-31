# Outputs for automated security response with Chronicle SOAR infrastructure

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Service Account Information
output "security_automation_service_account" {
  description = "Service account details for security automation"
  value = {
    email        = google_service_account.security_automation.email
    unique_id    = google_service_account.security_automation.unique_id
    display_name = google_service_account.security_automation.display_name
  }
}

# Pub/Sub Topic Information
output "pubsub_topics" {
  description = "Pub/Sub topics for security event processing"
  value = {
    security_events = {
      name = google_pubsub_topic.security_events.name
      id   = google_pubsub_topic.security_events.id
    }
    response_actions = {
      name = google_pubsub_topic.response_actions.name
      id   = google_pubsub_topic.response_actions.id
    }
  }
}

# Pub/Sub Subscription Information
output "pubsub_subscriptions" {
  description = "Pub/Sub subscriptions for Cloud Functions"
  value = {
    security_events = {
      name = google_pubsub_subscription.security_events_subscription.name
      id   = google_pubsub_subscription.security_events_subscription.id
    }
    response_actions = {
      name = google_pubsub_subscription.response_actions_subscription.name
      id   = google_pubsub_subscription.response_actions_subscription.id
    }
  }
}

# Cloud Functions Information
output "cloud_functions" {
  description = "Cloud Functions for security automation"
  value = {
    threat_enrichment = {
      name         = google_cloudfunctions_function.threat_enrichment.name
      source_url   = google_cloudfunctions_function.threat_enrichment.source_archive_bucket
      trigger_type = "Pub/Sub"
      trigger_topic = google_pubsub_topic.security_events.name
    }
    automated_response = {
      name         = google_cloudfunctions_function.automated_response.name
      source_url   = google_cloudfunctions_function.automated_response.source_archive_bucket
      trigger_type = "Pub/Sub"
      trigger_topic = google_pubsub_topic.response_actions.name
    }
  }
}

# Storage Bucket Information
output "storage_buckets" {
  description = "Cloud Storage buckets created for the solution"
  value = {
    function_source = {
      name = google_storage_bucket.function_source.name
      url  = google_storage_bucket.function_source.url
    }
    audit_logs = var.enable_audit_logging ? {
      name = google_storage_bucket.audit_logs[0].name
      url  = google_storage_bucket.audit_logs[0].url
    } : null
  }
}

# Security Command Center Configuration
output "security_command_center" {
  description = "Security Command Center notification configuration"
  value = var.organization_id != "" ? {
    notification_config_id = google_scc_notification_config.security_automation[0].config_id
    organization_id        = var.organization_id
    pubsub_topic          = google_pubsub_topic.security_events.id
    filter                = var.security_notification_filter
  } : {
    message = "Security Command Center notification not configured - organization_id not provided"
  }
}

# Secret Manager Information
output "secret_manager" {
  description = "Secret Manager secrets for Chronicle SOAR configuration"
  value = var.enable_secret_manager ? {
    chronicle_config = {
      secret_id = google_secret_manager_secret.chronicle_config[0].secret_id
      name      = google_secret_manager_secret.chronicle_config[0].name
    }
  } : null
}

# Chronicle SOAR Configuration
output "chronicle_soar_config" {
  description = "Chronicle SOAR playbook configuration details"
  value = {
    playbook_name              = var.chronicle_soar_config.playbook_name
    max_loop_iterations        = var.chronicle_soar_config.max_loop_iterations
    reputation_score_threshold = var.chronicle_soar_config.reputation_score_threshold
    scope_lock_enabled        = var.chronicle_soar_config.enable_scope_lock
  }
  sensitive = false
}

# Monitoring Information
output "monitoring" {
  description = "Cloud Monitoring resources for security automation"
  value = var.enable_monitoring ? {
    alert_policy = {
      id           = google_monitoring_alert_policy.function_errors[0].id
      display_name = google_monitoring_alert_policy.function_errors[0].display_name
    }
  } : null
}

# Logging Information
output "logging" {
  description = "Cloud Logging configuration for audit trails"
  value = var.enable_audit_logging ? {
    log_sink = {
      name        = google_logging_project_sink.security_audit[0].name
      destination = google_logging_project_sink.security_audit[0].destination
      filter      = google_logging_project_sink.security_audit[0].filter
    }
    retention_days = var.log_retention_days
  } : null
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_apis = "gcloud services list --enabled --project=${var.project_id}"
    check_functions = "gcloud functions list --project=${var.project_id} --region=${var.region}"
    check_topics = "gcloud pubsub topics list --project=${var.project_id}"
    check_subscriptions = "gcloud pubsub subscriptions list --project=${var.project_id}"
    test_security_events = "gcloud pubsub topics publish ${local.security_topic} --message='{\"test\": \"security_event\"}' --project=${var.project_id}"
  }
}

# Chronicle SOAR Integration URLs
output "chronicle_integration" {
  description = "Information for Chronicle SOAR integration"
  value = {
    console_url = "https://chronicle.security"
    pubsub_topics = {
      security_events_topic  = "projects/${var.project_id}/topics/${local.security_topic}"
      response_actions_topic = "projects/${var.project_id}/topics/${local.response_topic}"
    }
    cloud_functions = {
      threat_enrichment_name  = google_cloudfunctions_function.threat_enrichment.name
      automated_response_name = google_cloudfunctions_function.automated_response.name
    }
    service_account_email = google_service_account.security_automation.email
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the security automation solution"
  value = {
    cloud_functions = "~$10-30/month (based on execution frequency)"
    pubsub = "~$5-15/month (based on message volume)"
    storage = "~$5-10/month (function source + audit logs)"
    monitoring = "~$2-5/month (alert policies and metrics)"
    secret_manager = "~$1-3/month (configuration secrets)"
    security_command_center = "Contact Google Cloud Sales for Enterprise pricing"
    chronicle_soar = "Contact Google Cloud Sales for SOAR pricing"
    total_estimated = "$50-100/month (excluding SCC Premium and Chronicle SOAR licensing)"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the security automation setup"
  value = [
    "1. Access Chronicle SOAR console at https://chronicle.security",
    "2. Create new playbook using the configuration in Secret Manager",
    "3. Configure entity processing loops with the provided Pub/Sub topics",
    "4. Set up threat intelligence source integrations",
    "5. Test the automation workflow with simulated security events",
    "6. Configure notification channels for alert policies",
    "7. Review and adjust security response actions based on your environment"
  ]
}