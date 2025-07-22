# Real-Time Analytics Platform with Cloud Dataflow and Firestore
# This configuration creates a complete streaming analytics infrastructure on Google Cloud Platform

# Generate unique resource suffix to avoid naming conflicts
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.resource_prefix}-${var.environment}-${local.resource_suffix}"
  
  # Resource-specific names
  pubsub_topic_name      = "${local.common_name}-events-topic"
  pubsub_subscription    = "${local.common_name}-events-subscription"
  storage_bucket_name    = "${local.common_name}-analytics-archive"
  dataflow_job_name      = "${local.common_name}-streaming-pipeline"
  service_account_id     = "${var.resource_prefix}-dataflow-${local.resource_suffix}"
  
  # Merge default and custom labels
  common_labels = merge(var.labels, {
    environment    = var.environment
    resource-group = "real-time-analytics"
    created-by     = "terraform"
    suffix         = local.resource_suffix
  })
  
  # Pipeline configuration
  temp_location    = var.pipeline_temp_location != "" ? var.pipeline_temp_location : "gs://${google_storage_bucket.analytics_archive.name}/temp"
  staging_location = var.pipeline_staging_location != "" ? var.pipeline_staging_location : "gs://${google_storage_bucket.analytics_archive.name}/staging"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create App Engine application (required for Firestore)
resource "google_app_engine_application" "app" {
  project       = var.project_id
  location_id   = var.firestore_location_id
  database_type = var.firestore_database_type
  
  depends_on = [google_project_service.required_apis]
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Initialize Firestore database for real-time analytics storage
resource "google_firestore_database" "analytics_database" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location_id
  type        = var.firestore_database_type
  
  depends_on = [google_app_engine_application.app]
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Create Firestore composite indexes for optimized analytics queries
resource "google_firestore_index" "analytics_metrics_index" {
  project    = var.project_id
  database   = google_firestore_database.analytics_database.name
  collection = "analytics_metrics"
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  fields {
    field_path = "metric_type"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "value"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.analytics_database]
}

resource "google_firestore_index" "user_sessions_index" {
  project    = var.project_id
  database   = google_firestore_database.analytics_database.name
  collection = "user_sessions"
  
  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "session_start"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.analytics_database]
}

# Create Pub/Sub topic for streaming event ingestion
resource "google_pubsub_topic" "events_topic" {
  name    = local.pubsub_topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  message_retention_duration = "${var.pubsub_message_retention_duration}s"
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Dataflow pipeline consumption
resource "google_pubsub_subscription" "events_subscription" {
  name    = local.pubsub_subscription
  topic   = google_pubsub_topic.events_topic.name
  project = var.project_id
  
  labels = local.common_labels
  
  ack_deadline_seconds         = var.pubsub_ack_deadline_seconds
  message_retention_duration   = "${var.pubsub_message_retention_duration}s"
  retain_acked_messages       = false
  enable_exactly_once_delivery = true
  
  expiration_policy {
    ttl = "300000.5s" # 3.47 days
  }
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  depends_on = [google_pubsub_topic.events_topic]
}

# Create Cloud Storage bucket for data archival with lifecycle management
resource "google_storage_bucket" "analytics_archive" {
  name     = local.storage_bucket_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  storage_class = "STANDARD"
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_coldline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_archive
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Prevent accidental deletion in production
  force_destroy = var.storage_force_destroy
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Dataflow pipeline with least privilege access
resource "google_service_account" "dataflow_service_account" {
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = var.service_account_description
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Dataflow Worker role to service account
resource "google_project_iam_member" "dataflow_worker" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_service_account.email}"
  
  depends_on = [google_service_account.dataflow_service_account]
}

# Grant Pub/Sub Subscriber role for reading from subscription
resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.dataflow_service_account.email}"
  
  depends_on = [google_service_account.dataflow_service_account]
}

# Grant Firestore User role for writing analytics data
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.dataflow_service_account.email}"
  
  depends_on = [google_service_account.dataflow_service_account]
}

# Grant Storage Admin role for archiving raw events
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.dataflow_service_account.email}"
  
  depends_on = [google_service_account.dataflow_service_account]
}

# Create Cloud Storage objects for pipeline code deployment
resource "google_storage_bucket_object" "pipeline_requirements" {
  name   = "pipeline/requirements.txt"
  bucket = google_storage_bucket.analytics_archive.name
  
  content = <<EOF
apache-beam[gcp]==2.52.0
google-cloud-firestore==2.13.1
google-cloud-storage==2.10.0
EOF
  
  content_type = "text/plain"
  
  depends_on = [google_storage_bucket.analytics_archive]
}

resource "google_storage_bucket_object" "pipeline_code" {
  name   = "pipeline/streaming_analytics.py"
  bucket = google_storage_bucket.analytics_archive.name
  
  content = <<EOF
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms import window
import json
import logging
from datetime import datetime
from google.cloud import firestore

class ParseEventsFn(beam.DoFn):
    def process(self, element):
        try:
            data = json.loads(element.decode('utf-8'))
            # Add processing timestamp
            data['processed_at'] = datetime.utcnow().isoformat()
            yield data
        except Exception as e:
            logging.error(f"Error parsing event: {e}")

class AggregateMetrics(beam.DoFn):
    def process(self, element):
        window_start = element[1].start.to_utc_datetime()
        window_end = element[1].end.to_utc_datetime()
        events = element[0]
        
        # Calculate metrics
        total_events = len(events)
        event_types = {}
        user_sessions = {}
        
        for event in events:
            event_type = event.get('event_type', 'unknown')
            event_types[event_type] = event_types.get(event_type, 0) + 1
            
            user_id = event.get('user_id')
            if user_id:
                if user_id not in user_sessions:
                    user_sessions[user_id] = {
                        'events': 0,
                        'first_event': event.get('timestamp'),
                        'last_event': event.get('timestamp')
                    }
                user_sessions[user_id]['events'] += 1
                user_sessions[user_id]['last_event'] = event.get('timestamp')
        
        yield {
            'window_start': window_start.isoformat(),
            'window_end': window_end.isoformat(),
            'total_events': total_events,
            'event_types': event_types,
            'unique_users': len(user_sessions),
            'user_sessions': user_sessions
        }

class WriteToFirestore(beam.DoFn):
    def __init__(self, project_id):
        self.project_id = project_id
        self.db = None
    
    def setup(self):
        self.db = firestore.Client(project=self.project_id)
    
    def process(self, element):
        try:
            # Write aggregated metrics
            doc_ref = self.db.collection('analytics_metrics').document()
            doc_ref.set({
                'timestamp': element['window_start'],
                'metric_type': 'window_summary',
                'value': element['total_events'],
                'details': element
            })
            
            # Write user session data
            for user_id, session_data in element['user_sessions'].items():
                session_ref = self.db.collection('user_sessions').document()
                session_ref.set({
                    'user_id': user_id,
                    'session_start': element['window_start'],
                    'session_events': session_data['events'],
                    'first_event_time': session_data['first_event'],
                    'last_event_time': session_data['last_event']
                })
            
            logging.info(f"Written analytics data for window: {element['window_start']}")
        except Exception as e:
            logging.error(f"Error writing to Firestore: {e}")

def run_pipeline(argv=None):
    pipeline_options = PipelineOptions(argv)
    
    with beam.Pipeline(options=pipeline_options) as pipeline:
        # Read from Pub/Sub
        events = (pipeline 
                 | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                     subscription=f'projects/{pipeline_options.get_all_options()["project"]}/subscriptions/${local.pubsub_subscription}')
                 | 'Parse Events' >> beam.ParDo(ParseEventsFn()))
        
        # Process streaming events
        windowed_events = (events
                         | 'Window Events' >> beam.WindowInto(window.FixedWindows(60))  # 1-minute windows
                         | 'Group Events' >> beam.GroupBy(lambda x: 1).aggregate_field(lambda x: x, beam.combiners.ToListCombineFn(), 'events'))
        
        # Aggregate metrics
        aggregated = (windowed_events
                     | 'Aggregate Metrics' >> beam.ParDo(AggregateMetrics()))
        
        # Write to Firestore
        (aggregated
         | 'Write to Firestore' >> beam.ParDo(WriteToFirestore(pipeline_options.get_all_options()["project"])))
        
        # Archive raw events to Cloud Storage
        (events
         | 'Format for Storage' >> beam.Map(lambda x: json.dumps(x))
         | 'Write to Storage' >> beam.io.WriteToText(
             f'gs://${google_storage_bucket.analytics_archive.name}/raw-events/',
             file_name_suffix='.json',
             num_shards=0))

if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run_pipeline()
EOF
  
  content_type = "text/x-python"
  
  depends_on = [google_storage_bucket.analytics_archive]
}

# Create event generator script for testing
resource "google_storage_bucket_object" "event_generator" {
  name   = "scripts/generate_events.py"
  bucket = google_storage_bucket.analytics_archive.name
  
  content = <<EOF
import json
import random
import time
from datetime import datetime
from google.cloud import pubsub_v1
import sys

def generate_event():
    event_types = ['page_view', 'click', 'purchase', 'signup', 'login']
    user_ids = [f'user_{i:04d}' for i in range(1, 1001)]
    
    return {
        'event_id': f'evt_{int(time.time() * 1000)}_{random.randint(1000, 9999)}',
        'event_type': random.choice(event_types),
        'user_id': random.choice(user_ids),
        'timestamp': datetime.utcnow().isoformat(),
        'properties': {
            'page': random.choice(['/home', '/products', '/checkout', '/profile']),
            'device': random.choice(['mobile', 'desktop', 'tablet']),
            'value': random.uniform(10, 1000) if random.random() > 0.7 else None
        }
    }

def publish_events(project_id, topic_name, num_events=100):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    for i in range(num_events):
        event = generate_event()
        data = json.dumps(event).encode('utf-8')
        
        future = publisher.publish(topic_path, data)
        print(f'Published event {i+1}: {future.result()}')
        
        # Add some randomness to timing
        time.sleep(random.uniform(0.1, 0.5))

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print('Usage: python generate_events.py PROJECT_ID TOPIC_NAME NUM_EVENTS')
        sys.exit(1)
    
    project_id = sys.argv[1]
    topic_name = sys.argv[2]
    num_events = int(sys.argv[3])
    
    publish_events(project_id, topic_name, num_events)
EOF
  
  content_type = "text/x-python"
  
  depends_on = [google_storage_bucket.analytics_archive]
}

# Note: Dataflow job creation is commented out as it requires the pipeline code to be deployed
# and typically needs to be started after the infrastructure is ready. Enable this resource
# if you want Terraform to manage the Dataflow job lifecycle.

# resource "google_dataflow_job" "streaming_analytics_pipeline" {
#   name              = local.dataflow_job_name
#   template_gcs_path = "gs://dataflow-templates/latest/PubSub_to_BigQuery"
#   temp_gcs_location = local.temp_location
#   project           = var.project_id
#   region            = var.region
#   zone              = var.zone
#   
#   service_account_email = google_service_account.dataflow_service_account.email
#   network              = var.network_name != "" ? var.network_name : "default"
#   subnetwork           = var.subnet_name != "" ? var.subnet_name : null
#   use_private_ips      = !var.dataflow_use_public_ips
#   
#   machine_type = var.dataflow_machine_type
#   max_workers  = var.dataflow_max_workers
#   
#   labels = local.common_labels
#   
#   parameters = {
#     inputSubscription = google_pubsub_subscription.events_subscription.id
#     outputPath       = "gs://${google_storage_bucket.analytics_archive.name}/streaming-output/"
#   }
#   
#   depends_on = [
#     google_pubsub_subscription.events_subscription,
#     google_storage_bucket.analytics_archive,
#     google_project_iam_member.dataflow_worker,
#     google_project_iam_member.pubsub_subscriber,
#     google_project_iam_member.firestore_user,
#     google_project_iam_member.storage_admin
#   ]
# }