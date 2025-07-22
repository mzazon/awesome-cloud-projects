# Team Collaboration Insights with Workspace Events API and Cloud Functions
# This Terraform configuration deploys a complete analytics solution for Google Workspace collaboration

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Construct resource names with prefix and suffix
  resource_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    deployment  = "terraform"
    recipe      = "workspace-collaboration-insights"
  })
  
  # Service account email
  service_account_email = google_service_account.workspace_events_sa.email
  
  # Function source paths
  event_processor_source_dir = "${path.module}/function_code/event_processor"
  analytics_api_source_dir   = "${path.module}/function_code/analytics_api"
}

# Enable required APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "workspaceevents.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Workspace Events API
resource "google_service_account" "workspace_events_sa" {
  account_id   = "${var.resource_prefix}-events-sa-${local.resource_suffix}"
  display_name = var.service_account_display_name
  description  = "Service account for Workspace Events API integration and Cloud Functions"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Pub/Sub publisher role to service account
resource "google_project_iam_member" "workspace_events_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.workspace_events_sa]
}

# Grant Firestore user role to service account
resource "google_project_iam_member" "workspace_events_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.workspace_events_sa]
}

# Grant Cloud Functions invoker role for analytics API
resource "google_project_iam_member" "functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${local.service_account_email}"
  
  depends_on = [google_service_account.workspace_events_sa]
}

# Create Pub/Sub topic for Workspace events
resource "google_pubsub_topic" "workspace_events_topic" {
  name    = "${var.resource_prefix}-${var.pubsub_topic_name}-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels
  
  # Enable message ordering for consistent event processing
  message_retention_duration = "86400s" # 24 hours
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Functions trigger
resource "google_pubsub_subscription" "workspace_events_subscription" {
  name    = "${var.resource_prefix}-${var.pubsub_subscription_name}-${local.resource_suffix}"
  topic   = google_pubsub_topic.workspace_events_topic.name
  project = var.project_id
  labels  = local.common_labels
  
  # Configure acknowledgment deadline for event processing
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Enable exactly-once delivery for data consistency
  enable_exactly_once_delivery = true
  
  # Configure retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter topic for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_pubsub_topic.workspace_events_topic]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter_topic" {
  name    = "${var.resource_prefix}-dead-letter-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore database for analytics data storage
resource "google_firestore_database" "workspace_analytics_db" {
  project                     = var.project_id
  name                       = "(default)"
  location_id                = var.firestore_location
  type                       = var.firestore_type
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source_bucket" {
  name                        = "${var.project_id}-function-source-${local.resource_suffix}"
  location                    = var.region
  project                     = var.project_id
  labels                      = local.common_labels
  force_destroy               = true
  uniform_bucket_level_access = true
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create event processor function source directory and files
resource "local_file" "event_processor_main" {
  filename = "${local.event_processor_source_dir}/main.py"
  content = <<-EOF
import json
import base64
from google.cloud import firestore
from datetime import datetime
import functions_framework
import os

# Initialize Firestore client
db = firestore.Client()

@functions_framework.cloud_event
def process_workspace_event(cloud_event):
    """Process Google Workspace events and store analytics data."""
    
    try:
        # Decode event data
        event_data = json.loads(base64.b64decode(cloud_event.data['message']['data']))
        event_type = cloud_event.data['message']['attributes'].get('ce-type', '')
        event_time = cloud_event.data['message']['attributes'].get('ce-time', '')
        
        # Extract collaboration insights
        insights = extract_collaboration_insights(event_data, event_type)
        
        # Store in Firestore
        doc_ref = db.collection('collaboration_events').document()
        doc_ref.set({
            'event_type': event_type,
            'timestamp': datetime.fromisoformat(event_time.replace('Z', '+00:00')),
            'insights': insights,
            'raw_event': event_data,
            'processed_at': datetime.now()
        })
        
        # Update team metrics
        update_team_metrics(insights)
        
        print(f"Successfully processed {event_type} event at {event_time}")
        
    except Exception as e:
        print(f"Error processing workspace event: {str(e)}")
        raise

def extract_collaboration_insights(event_data, event_type):
    """Extract meaningful collaboration insights from workspace events."""
    insights = {
        'event_category': 'unknown',
        'participants': [],
        'metadata': {}
    }
    
    try:
        if 'chat.message' in event_type:
            insights.update({
                'event_category': 'chat',
                'interaction_type': 'chat_message',
                'participants': [event_data.get('sender', {}).get('name', 'unknown')],
                'metadata': {
                    'space_id': event_data.get('space', {}).get('name'),
                    'message_type': event_data.get('messageType', 'text')
                }
            })
        elif 'drive.file' in event_type:
            insights.update({
                'event_category': 'drive',
                'interaction_type': 'file_collaboration',
                'participants': [event_data.get('actor', {}).get('name', 'unknown')],
                'metadata': {
                    'file_type': event_data.get('mimeType', 'unknown'),
                    'sharing_activity': event_type.split('.')[-1],
                    'file_id': event_data.get('id')
                }
            })
        elif 'meet.conference' in event_type:
            participants = event_data.get('participants', [])
            insights.update({
                'event_category': 'meet',
                'interaction_type': 'meeting_activity',
                'participants': [p.get('name', 'unknown') for p in participants],
                'metadata': {
                    'conference_id': event_data.get('conferenceRecord', {}).get('name'),
                    'duration': event_data.get('conferenceRecord', {}).get('duration'),
                    'participants_count': len(participants),
                    'activity_type': event_type.split('.')[-1]
                }
            })
    except Exception as e:
        print(f"Error extracting insights: {str(e)}")
        insights['error'] = str(e)
    
    return insights

def update_team_metrics(insights):
    """Update aggregated team collaboration metrics."""
    try:
        from google.cloud.firestore import Increment
        
        metrics_ref = db.collection('team_metrics').document('daily_summary')
        
        # Prepare metric updates
        updates = {
            'last_updated': datetime.now(),
            'total_events': Increment(1)
        }
        
        # Add category-specific metrics
        event_category = insights.get('event_category', 'unknown')
        interaction_type = insights.get('interaction_type', 'unknown')
        
        updates[f"{event_category}_events"] = Increment(1)
        updates[f"{interaction_type}_count"] = Increment(1)
        
        # Update participant count if available
        participant_count = len(insights.get('participants', []))
        if participant_count > 0:
            updates['unique_participants_today'] = Increment(participant_count)
        
        # Use transaction for atomic updates
        @firestore.transactional
        def update_metrics(transaction, metrics_ref):
            transaction.update(metrics_ref, updates)
        
        transaction = db.transaction()
        update_metrics(transaction, metrics_ref)
        
    except Exception as e:
        print(f"Error updating team metrics: {str(e)}")
        # Continue processing even if metrics update fails
EOF

  depends_on = [google_storage_bucket.function_source_bucket]
}

resource "local_file" "event_processor_requirements" {
  filename = "${local.event_processor_source_dir}/requirements.txt"
  content = <<-EOF
google-cloud-firestore>=2.16.0
functions-framework>=3.5.0
google-cloud-logging>=3.8.0
EOF

  depends_on = [local_file.event_processor_main]
}

# Create analytics API function source directory and files
resource "local_file" "analytics_api_main" {
  filename = "${local.analytics_api_source_dir}/main.py"
  content = <<-EOF
import json
from google.cloud import firestore
from datetime import datetime, timedelta
import functions_framework
from flask import jsonify, request
import os

# Initialize Firestore client
db = firestore.Client()

@functions_framework.http
def get_collaboration_analytics(request):
    """HTTP endpoint for retrieving collaboration analytics."""
    
    try:
        # Enable CORS for web applications
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        # Parse query parameters
        days = int(request.args.get('days', 7))
        team_id = request.args.get('team_id', 'all')
        event_type = request.args.get('event_type', 'all')
        
        # Validate parameters
        if days > 365:
            return jsonify({'error': 'Maximum days allowed is 365'}), 400, headers
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        # Query collaboration events
        events_ref = db.collection('collaboration_events')
        query = events_ref.where('timestamp', '>=', start_date) \
                         .where('timestamp', '<=', end_date)
        
        # Apply additional filters
        if event_type != 'all':
            query = query.where('insights.event_category', '==', event_type)
        
        # Limit query results for performance
        query = query.limit(10000)
        
        events = []
        for doc in query.stream():
            event_data = doc.to_dict()
            events.append(event_data)
        
        # Calculate analytics
        analytics = calculate_team_analytics(events, days)
        
        # Get team metrics summary
        team_metrics = get_team_metrics_summary()
        
        response_data = {
            'period': f'{days} days',
            'date_range': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'total_events': len(events),
            'analytics': analytics,
            'team_metrics': team_metrics,
            'generated_at': datetime.now().isoformat(),
            'filters': {
                'team_id': team_id,
                'event_type': event_type
            }
        }
        
        return jsonify(response_data), 200, headers
        
    except Exception as e:
        error_response = {
            'error': 'Internal server error',
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }
        return jsonify(error_response), 500, headers

def calculate_team_analytics(events, days):
    """Calculate team collaboration analytics from events."""
    analytics = {
        'event_categories': {},
        'interaction_types': {},
        'daily_activity': {},
        'hourly_patterns': {},
        'top_participants': {},
        'collaboration_score': 0,
        'trends': {}
    }
    
    try:
        for event in events:
            insights = event.get('insights', {})
            timestamp = event.get('timestamp')
            
            if not timestamp:
                continue
                
            # Convert timestamp if it's a string
            if isinstance(timestamp, str):
                timestamp = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            
            # Count event categories
            category = insights.get('event_category', 'unknown')
            analytics['event_categories'][category] = \
                analytics['event_categories'].get(category, 0) + 1
            
            # Count interaction types
            interaction_type = insights.get('interaction_type', 'unknown')
            analytics['interaction_types'][interaction_type] = \
                analytics['interaction_types'].get(interaction_type, 0) + 1
            
            # Group by day
            event_date = timestamp.date().isoformat()
            analytics['daily_activity'][event_date] = \
                analytics['daily_activity'].get(event_date, 0) + 1
            
            # Group by hour of day
            hour = timestamp.hour
            analytics['hourly_patterns'][str(hour)] = \
                analytics['hourly_patterns'].get(str(hour), 0) + 1
            
            # Count participants
            participants = insights.get('participants', [])
            for participant in participants:
                if participant and participant != 'unknown':
                    analytics['top_participants'][participant] = \
                        analytics['top_participants'].get(participant, 0) + 1
        
        # Calculate collaboration score (simplified metric)
        total_interactions = sum(analytics['interaction_types'].values())
        unique_types = len(analytics['interaction_types'])
        unique_participants = len(analytics['top_participants'])
        
        # Collaboration score based on diversity and activity
        if total_interactions > 0:
            diversity_factor = unique_types * unique_participants
            activity_factor = min(total_interactions / days, 50)  # Cap at 50 per day
            analytics['collaboration_score'] = min(100, diversity_factor + activity_factor)
        
        # Calculate trends (simple day-over-day comparison)
        daily_values = list(analytics['daily_activity'].values())
        if len(daily_values) >= 2:
            recent_avg = sum(daily_values[-3:]) / min(3, len(daily_values[-3:]))
            earlier_avg = sum(daily_values[:-3]) / max(1, len(daily_values[:-3]))
            if earlier_avg > 0:
                analytics['trends']['activity_change_percent'] = \
                    ((recent_avg - earlier_avg) / earlier_avg) * 100
        
        # Sort top participants by activity
        analytics['top_participants'] = dict(
            sorted(analytics['top_participants'].items(), 
                  key=lambda x: x[1], reverse=True)[:10]
        )
        
    except Exception as e:
        print(f"Error calculating analytics: {str(e)}")
        analytics['calculation_error'] = str(e)
    
    return analytics

def get_team_metrics_summary():
    """Get current team metrics summary from Firestore."""
    try:
        metrics_doc = db.collection('team_metrics').document('daily_summary').get()
        if metrics_doc.exists:
            return metrics_doc.to_dict()
        else:
            return {'status': 'No metrics available yet'}
    except Exception as e:
        print(f"Error retrieving team metrics: {str(e)}")
        return {'error': f'Failed to retrieve metrics: {str(e)}'}
EOF

  depends_on = [local_file.event_processor_requirements]
}

resource "local_file" "analytics_api_requirements" {
  filename = "${local.analytics_api_source_dir}/requirements.txt"
  content = <<-EOF
google-cloud-firestore>=2.16.0
functions-framework>=3.5.0
flask>=2.3.0
google-cloud-logging>=3.8.0
EOF

  depends_on = [local_file.analytics_api_main]
}

# Create zip archives for function source code
data "archive_file" "event_processor_source" {
  type        = "zip"
  source_dir  = local.event_processor_source_dir
  output_path = "${path.module}/event_processor_source.zip"
  
  depends_on = [
    local_file.event_processor_main,
    local_file.event_processor_requirements
  ]
}

data "archive_file" "analytics_api_source" {
  type        = "zip"
  source_dir  = local.analytics_api_source_dir
  output_path = "${path.module}/analytics_api_source.zip"
  
  depends_on = [
    local_file.analytics_api_main,
    local_file.analytics_api_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "event_processor_source" {
  name   = "event_processor_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.event_processor_source.output_path
  
  # Ensure function redeployment when source changes
  metadata = {
    source_hash = data.archive_file.event_processor_source.output_base64sha256
  }
}

resource "google_storage_bucket_object" "analytics_api_source" {
  name   = "analytics_api_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.analytics_api_source.output_path
  
  # Ensure function redeployment when source changes
  metadata = {
    source_hash = data.archive_file.analytics_api_source.output_base64sha256
  }
}

# Deploy Cloud Function for event processing
resource "google_cloudfunctions2_function" "process_workspace_events" {
  name     = "${var.resource_prefix}-process-events-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "process_workspace_event"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.event_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.event_processor_memory}Mi"
    timeout_seconds                  = var.event_processor_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      GCP_PROJECT     = var.project_id
      FIRESTORE_PROJECT = var.project_id
    }
    
    service_account_email = local.service_account_email
    
    # Enable VPC connector if needed
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.workspace_events_topic.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = local.service_account_email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.event_processor_source,
    google_pubsub_topic.workspace_events_topic,
    google_firestore_database.workspace_analytics_db
  ]
}

# Deploy Cloud Function for analytics API
resource "google_cloudfunctions2_function" "collaboration_analytics" {
  name     = "${var.resource_prefix}-analytics-api-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "get_collaboration_analytics"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.analytics_api_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.analytics_api_memory}Mi"
    timeout_seconds                  = var.analytics_api_timeout
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    
    environment_variables = {
      GCP_PROJECT = var.project_id
      FIRESTORE_PROJECT = var.project_id
    }
    
    service_account_email = local.service_account_email
    
    # Allow external access for API functionality
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.analytics_api_source,
    google_firestore_database.workspace_analytics_db
  ]
}

# Configure IAM for analytics API function (conditional on authentication setting)
resource "google_cloudfunctions2_function_iam_member" "analytics_api_invoker" {
  count = var.allow_unauthenticated_analytics_api ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.collaboration_analytics.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Firestore security rules
resource "google_firebaserules_ruleset" "firestore_rules" {
  project = var.project_id
  
  source {
    files {
      name    = "firestore.rules"
      content = <<-EOF
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read access to collaboration events for authenticated users
    match /collaboration_events/{document} {
      allow read: if request.auth != null || 
                     request.auth.token.email.matches('.*@${var.project_id}.iam.gserviceaccount.com');
      allow write: if request.auth.token.email.matches('.*@${var.project_id}.iam.gserviceaccount.com');
    }
    
    // Allow read access to team metrics
    match /team_metrics/{document} {
      allow read: if request.auth != null ||
                     request.auth.token.email.matches('.*@${var.project_id}.iam.gserviceaccount.com');
      allow write: if request.auth.token.email.matches('.*@${var.project_id}.iam.gserviceaccount.com');
    }
    
    // Deny all other access by default
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
EOF
    }
  }
  
  depends_on = [google_firestore_database.workspace_analytics_db]
}

# Apply Firestore security rules
resource "google_firebaserules_release" "firestore_rules_release" {
  project      = var.project_id
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore_rules.name
  
  depends_on = [google_firebaserules_ruleset.firestore_rules]
}

# Optional: Create Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "${var.resource_prefix} Function Error Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_cloudfunctions2_function.process_workspace_events,
    google_cloudfunctions2_function.collaboration_analytics
  ]
}

# Create audit log configuration
resource "google_project_iam_audit_config" "audit_logs" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id
  service = "allServices"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}