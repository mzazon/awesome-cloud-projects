# Outputs for Team Collaboration Insights with Workspace Events API
# These outputs provide essential information for accessing and managing the deployed solution

# Project and Infrastructure Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource uniqueness"
  value       = random_id.suffix.hex
  sensitive   = false
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the service account for Workspace Events API"
  value       = google_service_account.workspace_events_sa.email
}

output "service_account_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.workspace_events_sa.unique_id
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for Workspace events"
  value       = google_pubsub_topic.workspace_events_topic.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.workspace_events_topic.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.workspace_events_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.workspace_events_subscription.id
}

output "dead_letter_topic_name" {
  description = "Name of the dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter_topic.name
}

# Cloud Functions Information
output "event_processor_function_name" {
  description = "Name of the event processing Cloud Function"
  value       = google_cloudfunctions2_function.process_workspace_events.name
}

output "event_processor_function_url" {
  description = "URL of the event processing Cloud Function (internal only)"
  value       = google_cloudfunctions2_function.process_workspace_events.service_config[0].uri
}

output "analytics_api_function_name" {
  description = "Name of the analytics API Cloud Function"
  value       = google_cloudfunctions2_function.collaboration_analytics.name
}

output "analytics_api_function_url" {
  description = "HTTP URL of the analytics API Cloud Function"
  value       = google_cloudfunctions2_function.collaboration_analytics.service_config[0].uri
}

output "analytics_api_trigger_url" {
  description = "Public HTTP trigger URL for the analytics API"
  value       = google_cloudfunctions2_function.collaboration_analytics.url
}

# Firestore Database Information
output "firestore_database_id" {
  description = "ID of the Firestore database"
  value       = google_firestore_database.workspace_analytics_db.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.workspace_analytics_db.location_id
}

output "firestore_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.workspace_analytics_db.type
}

# Storage Information
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source_bucket.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source_bucket.url
}

# Workspace Events API Configuration
output "workspace_events_api_setup_instructions" {
  description = "Instructions for setting up Workspace Events API subscriptions"
  value = <<-EOT
To complete the Workspace Events API setup, follow these steps:

1. Create Chat Events Subscription:
   curl -X POST "https://workspaceevents.googleapis.com/v1/subscriptions" \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "projects/${var.project_id}/subscriptions/chat-collaboration-events",
       "targetResource": "//chat.googleapis.com/spaces/-",
       "eventTypes": [
         "google.workspace.chat.message.v1.created",
         "google.workspace.chat.space.v1.updated",
         "google.workspace.chat.membership.v1.created"
       ],
       "notificationEndpoint": {
         "pubsubTopic": "${google_pubsub_topic.workspace_events_topic.id}"
       },
       "payloadOptions": {
         "includeResource": true
       }
     }'

2. Create Drive Events Subscription:
   curl -X POST "https://workspaceevents.googleapis.com/v1/subscriptions" \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "projects/${var.project_id}/subscriptions/drive-collaboration-events",
       "targetResource": "//drive.googleapis.com/files/-",
       "eventTypes": [
         "google.workspace.drive.file.v1.created",
         "google.workspace.drive.file.v1.updated",
         "google.workspace.drive.file.v1.accessProposalCreated"
       ],
       "notificationEndpoint": {
         "pubsubTopic": "${google_pubsub_topic.workspace_events_topic.id}"
       },
       "payloadOptions": {
         "includeResource": false
       }
     }'

3. Create Meet Events Subscription:
   curl -X POST "https://workspaceevents.googleapis.com/v1/subscriptions" \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "projects/${var.project_id}/subscriptions/meet-collaboration-events",
       "targetResource": "//meet.googleapis.com/conferenceRecords/-",
       "eventTypes": [
         "google.workspace.meet.conference.v2.started",
         "google.workspace.meet.conference.v2.ended",
         "google.workspace.meet.participant.v2.joined",
         "google.workspace.meet.participant.v2.left"
       ],
       "notificationEndpoint": {
         "pubsubTopic": "${google_pubsub_topic.workspace_events_topic.id}"
       },
       "payloadOptions": {
         "includeResource": true
       }
     }'

Note: You must have domain administrator privileges to create Workspace Events API subscriptions.
EOT
}

# API Testing Information
output "analytics_api_test_commands" {
  description = "Example commands for testing the analytics API"
  value = <<-EOT
Test the analytics API with these commands:

1. Basic analytics query (last 7 days):
   curl "${google_cloudfunctions2_function.collaboration_analytics.url}?days=7"

2. Get analytics for specific event type:
   curl "${google_cloudfunctions2_function.collaboration_analytics.url}?days=30&event_type=chat"

3. Get team metrics for last 14 days:
   curl "${google_cloudfunctions2_function.collaboration_analytics.url}?days=14&team_id=all"

4. Test with browser:
   Open: ${google_cloudfunctions2_function.collaboration_analytics.url}?days=7

Note: If authentication is enabled, include appropriate authorization headers.
EOT
}

# Monitoring and Logging URLs
output "cloud_logging_url" {
  description = "URL to view Cloud Function logs in Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_function%22%0Aresource.labels.function_name%3D~%22${var.resource_prefix}.*%22;project=${var.project_id}"
}

output "cloud_monitoring_url" {
  description = "URL to view Cloud Function metrics in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards;project=${var.project_id}"
}

output "firestore_console_url" {
  description = "URL to view Firestore data in Google Cloud Console"
  value       = "https://console.cloud.google.com/firestore/data;project=${var.project_id}"
}

output "pubsub_console_url" {
  description = "URL to view Pub/Sub topics and subscriptions in Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudpubsub;project=${var.project_id}"
}

# Security and Access Information
output "firestore_security_rules_applied" {
  description = "Indicates whether Firestore security rules have been applied"
  value       = "Security rules applied - only authenticated users and service accounts can access data"
}

output "required_apis_enabled" {
  description = "List of APIs that have been enabled for this project"
  value = [
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "workspaceevents.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Cost Management Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed solution"
  value = <<-EOT
Cost Optimization Tips:
1. Monitor Cloud Function invocations and adjust memory allocations if needed
2. Review Firestore read/write operations and optimize queries
3. Set up budget alerts in Google Cloud Console
4. Consider using Cloud Functions minimum instances only if consistent low latency is required
5. Review Pub/Sub message retention settings based on your needs
6. Clean up old function source code in Cloud Storage bucket periodically
7. Monitor dead letter topic for failed messages that might indicate issues

Estimated monthly costs (with moderate usage):
- Cloud Functions: $5-15 (based on invocations and memory)
- Firestore: $5-20 (based on reads/writes and storage)
- Pub/Sub: $1-5 (based on message volume)
- Cloud Storage: $1-3 (for function source code)
EOT
}

# Workspace Domain Configuration
output "workspace_domain_configuration" {
  description = "Information about Workspace domain configuration requirements"
  value = var.workspace_domain != "" ? "Workspace domain: ${var.workspace_domain}" : "Workspace domain not configured - manual setup required"
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
Next Steps:
1. Configure Google Workspace Events API subscriptions using the provided commands
2. Test the analytics API endpoint to verify functionality
3. Set up monitoring alerts for Cloud Functions
4. Configure authentication for the analytics API if needed
5. Integrate the analytics API with your dashboard or BI tools
6. Review Firestore security rules and adjust as needed for your organization
7. Set up regular data exports or backup procedures for analytics data

For troubleshooting, check the Cloud Function logs and Firestore console for data flow.
EOT
}