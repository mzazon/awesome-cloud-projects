# Outputs for Event-Driven Incident Response System
# This file provides important information about the deployed infrastructure

# Project and Resource Information
output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for naming resources"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "The random suffix used for resource uniqueness"
  value       = local.random_suffix
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the incident response service account"
  value       = google_service_account.incident_response.email
}

output "service_account_name" {
  description = "Name of the incident response service account"
  value       = google_service_account.incident_response.name
}

output "service_account_unique_id" {
  description = "Unique ID of the incident response service account"
  value       = google_service_account.incident_response.unique_id
}

# Cloud Storage Information
output "source_bucket_name" {
  description = "Name of the source code storage bucket"
  value       = google_storage_bucket.source_bucket.name
}

output "source_bucket_url" {
  description = "URL of the source code storage bucket"
  value       = google_storage_bucket.source_bucket.url
}

# Pub/Sub Topic Information
output "pubsub_topics" {
  description = "Information about created Pub/Sub topics"
  value = {
    for key, topic in google_pubsub_topic.incident_topics : key => {
      name = topic.name
      id   = topic.id
    }
  }
}

output "incident_alerts_topic" {
  description = "Name of the incident alerts Pub/Sub topic"
  value       = google_pubsub_topic.incident_topics["incident_alerts"].name
}

output "remediation_topic" {
  description = "Name of the remediation Pub/Sub topic"
  value       = google_pubsub_topic.incident_topics["remediation"].name
}

output "escalation_topic" {
  description = "Name of the escalation Pub/Sub topic"
  value       = google_pubsub_topic.incident_topics["escalation"].name
}

output "notification_topic" {
  description = "Name of the notification Pub/Sub topic"
  value       = google_pubsub_topic.incident_topics["notification"].name
}

# Cloud Functions Information
output "triage_function_name" {
  description = "Name of the incident triage Cloud Function"
  value       = google_cloudfunctions2_function.triage_function.name
}

output "triage_function_url" {
  description = "URL of the incident triage Cloud Function"
  value       = google_cloudfunctions2_function.triage_function.service_config[0].uri
}

output "notification_function_name" {
  description = "Name of the notification Cloud Function"
  value       = google_cloudfunctions2_function.notification_function.name
}

output "notification_function_url" {
  description = "URL of the notification Cloud Function"
  value       = google_cloudfunctions2_function.notification_function.service_config[0].uri
}

# Cloud Run Service Information
output "remediation_service_name" {
  description = "Name of the remediation Cloud Run service"
  value       = google_cloud_run_v2_service.remediation_service.name
}

output "remediation_service_url" {
  description = "URL of the remediation Cloud Run service"
  value       = google_cloud_run_v2_service.remediation_service.uri
}

output "escalation_service_name" {
  description = "Name of the escalation Cloud Run service"
  value       = google_cloud_run_v2_service.escalation_service.name
}

output "escalation_service_url" {
  description = "URL of the escalation Cloud Run service"
  value       = google_cloud_run_v2_service.escalation_service.uri
}

# Eventarc Trigger Information
output "eventarc_triggers" {
  description = "Information about created Eventarc triggers"
  value = var.eventarc_config.enabled ? {
    monitoring_alert = {
      name     = google_eventarc_trigger.monitoring_alert_trigger[0].name
      location = google_eventarc_trigger.monitoring_alert_trigger[0].location
      uid      = google_eventarc_trigger.monitoring_alert_trigger[0].uid
    }
    remediation = {
      name     = google_eventarc_trigger.remediation_trigger[0].name
      location = google_eventarc_trigger.remediation_trigger[0].location
      uid      = google_eventarc_trigger.remediation_trigger[0].uid
    }
    escalation = {
      name     = google_eventarc_trigger.escalation_trigger[0].name
      location = google_eventarc_trigger.escalation_trigger[0].location
      uid      = google_eventarc_trigger.escalation_trigger[0].uid
    }
  } : {}
}

# Monitoring Information
output "monitoring_notification_channels" {
  description = "Information about created monitoring notification channels"
  value = var.monitoring_config.enabled ? {
    for key, channel in google_monitoring_notification_channel.notification_channels : key => {
      name         = channel.name
      display_name = channel.display_name
      type         = channel.type
    }
  } : {}
}

output "monitoring_alert_policies" {
  description = "Information about created monitoring alert policies"
  value = var.monitoring_config.enabled ? {
    for key, policy in google_monitoring_alert_policy.alert_policies : key => {
      name         = policy.name
      display_name = policy.display_name
      combiner     = policy.combiner
    }
  } : {}
}

# Testing and Verification Information
output "testing_commands" {
  description = "Commands to test the incident response system"
  value = {
    test_incident_alert = "gcloud pubsub topics publish ${google_pubsub_topic.incident_topics["incident_alerts"].name} --message='{\"incident\": {\"incident_id\": \"test-001\", \"condition_name\": \"high_cpu_utilization\", \"resource_name\": \"test-vm\"}, \"timestamp\": \"2025-07-12T10:00:00Z\"}'"
    
    view_triage_logs = "gcloud functions logs read ${google_cloudfunctions2_function.triage_function.name} --region=${var.region} --limit=10"
    
    view_notification_logs = "gcloud functions logs read ${google_cloudfunctions2_function.notification_function.name} --region=${var.region} --limit=10"
    
    view_remediation_logs = "gcloud logs read 'resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.remediation_service.name}' --limit=10"
    
    view_escalation_logs = "gcloud logs read 'resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.escalation_service.name}' --limit=10"
    
    list_eventarc_triggers = "gcloud eventarc triggers list --location=${var.region}"
    
    list_alert_policies = "gcloud alpha monitoring policies list --format='table(displayName,enabled,conditions[0].displayName)'"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    project_id = var.project_id
    region     = var.region
    environment = var.environment
    
    service_account = google_service_account.incident_response.email
    
    storage = {
      source_bucket = google_storage_bucket.source_bucket.name
    }
    
    pubsub_topics = {
      incident_alerts = google_pubsub_topic.incident_topics["incident_alerts"].name
      remediation     = google_pubsub_topic.incident_topics["remediation"].name
      escalation      = google_pubsub_topic.incident_topics["escalation"].name
      notification    = google_pubsub_topic.incident_topics["notification"].name
    }
    
    cloud_functions = {
      triage_function      = google_cloudfunctions2_function.triage_function.name
      notification_function = google_cloudfunctions2_function.notification_function.name
    }
    
    cloud_run_services = {
      remediation_service = google_cloud_run_v2_service.remediation_service.name
      escalation_service  = google_cloud_run_v2_service.escalation_service.name
    }
    
    eventarc_triggers = var.eventarc_config.enabled ? {
      monitoring_alert = google_eventarc_trigger.monitoring_alert_trigger[0].name
      remediation      = google_eventarc_trigger.remediation_trigger[0].name
      escalation       = google_eventarc_trigger.escalation_trigger[0].name
    } : {}
    
    monitoring = var.monitoring_config.enabled ? {
      notification_channels = [
        for channel in google_monitoring_notification_channel.notification_channels : channel.name
      ]
      alert_policies = [
        for policy in google_monitoring_alert_policy.alert_policies : policy.name
      ]
    } : {}
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    cloud_functions = {
      triage_function = {
        description = "Incident triage function (512MB, 540s timeout)"
        estimate    = "$20-50 depending on invocation frequency"
      }
      notification_function = {
        description = "Notification function (256MB, 300s timeout)"
        estimate    = "$10-30 depending on invocation frequency"
      }
    }
    
    cloud_run = {
      remediation_service = {
        description = "Remediation service (1 CPU, 1Gi memory)"
        estimate    = "$15-40 depending on usage"
      }
      escalation_service = {
        description = "Escalation service (1 CPU, 512Mi memory)"
        estimate    = "$10-25 depending on usage"
      }
    }
    
    pubsub = {
      description = "4 Pub/Sub topics with standard message retention"
      estimate    = "$1-5 depending on message volume"
    }
    
    storage = {
      description = "Cloud Storage for source code"
      estimate    = "$1-3 for small source code files"
    }
    
    monitoring = {
      description = "Cloud Monitoring alerts and notification channels"
      estimate    = "$5-15 depending on alert frequency"
    }
    
    total_estimated_range = "$62-168 per month for moderate usage"
    
    notes = [
      "Actual costs depend on usage patterns and event frequency",
      "Cloud Functions and Cloud Run scale to zero when not in use",
      "Monitor billing dashboard for actual costs",
      "Set up budget alerts to avoid unexpected charges"
    ]
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    service_account_roles = var.iam_config.roles
    
    network_security = {
      cloud_functions_ingress = "Internal only"
      cloud_run_ingress      = "Internal only"
    }
    
    authentication = {
      eventarc_service_account = google_service_account.incident_response.email
      functions_service_account = google_service_account.incident_response.email
      cloud_run_service_account = google_service_account.incident_response.email
    }
    
    best_practices = [
      "All services use dedicated service account with least privilege",
      "Network ingress restricted to internal traffic only",
      "Function and service authentication required",
      "Resource labels applied for governance"
    ]
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Create and upload container images for Cloud Run services",
    "2. Test the incident response workflow using the testing commands",
    "3. Configure monitoring notification channels with real email addresses",
    "4. Set up external integrations (Slack, PagerDuty, etc.)",
    "5. Customize alert policies for your specific monitoring requirements",
    "6. Review and adjust resource scaling configurations",
    "7. Set up budget alerts to monitor costs",
    "8. Implement proper secret management for external API keys",
    "9. Configure VPC connectivity if needed for internal services",
    "10. Set up CI/CD pipeline for automated deployments"
  ]
}