# ============================================================================
# VIDEO CONTENT MODERATION INFRASTRUCTURE
# ============================================================================
# This Terraform configuration deploys a complete video content moderation
# workflow using Google Cloud Video Intelligence API, Cloud Scheduler,
# Cloud Functions, and Cloud Storage.
# ============================================================================

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  # Resource naming with consistent suffix
  suffix                = var.bucket_name_suffix != null ? var.bucket_name_suffix : random_id.suffix.hex
  bucket_name          = "${var.resource_prefix}-${local.suffix}"
  function_name        = "${var.resource_prefix}-function-${local.suffix}"
  scheduler_job_name   = "${var.resource_prefix}-job-${local.suffix}"
  pubsub_topic_name    = "${var.resource_prefix}-topic-${local.suffix}"
  service_account_name = "${var.resource_prefix}-scheduler-${local.suffix}"
  
  # Function source code directory (will be created by local-exec)
  function_source_dir = "${path.module}/function-source"
  
  # Labels for all resources
  common_labels = merge(var.labels, {
    component = "video-moderation"
    version   = "1.0"
  })
}

# ============================================================================
# API ENABLEMENT
# ============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "videointelligence.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ============================================================================
# STORAGE LAYER
# ============================================================================

# Cloud Storage bucket for video processing workflow
resource "google_storage_bucket" "video_bucket" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age
      }
      action {
        type = "Delete"
      }
    }
  }

  # Public access prevention for security
  public_access_prevention = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in the bucket
resource "google_storage_bucket_object" "folders" {
  for_each = toset(["processing/", "approved/", "flagged/"])
  
  name    = "${each.value}.keep"
  content = "This folder is for ${trimright(each.value, "/")} videos"
  bucket  = google_storage_bucket.video_bucket.name
}

# ============================================================================
# MESSAGING LAYER
# ============================================================================

# Pub/Sub topic for video moderation events
resource "google_pubsub_topic" "video_moderation" {
  name    = local.pubsub_topic_name
  project = var.project_id

  # Message retention for reliability
  message_retention_duration = var.message_retention_duration

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for Cloud Function trigger
resource "google_pubsub_subscription" "video_moderation_sub" {
  name    = "${local.pubsub_topic_name}-sub"
  topic   = google_pubsub_topic.video_moderation.name
  project = var.project_id

  # Configure acknowledgment deadline for video processing
  ack_deadline_seconds = var.ack_deadline_seconds

  # Message retention configuration
  message_retention_duration = var.message_retention_duration

  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.video_moderation_dlq.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels
}

# Dead letter queue for failed processing
resource "google_pubsub_topic" "video_moderation_dlq" {
  name    = "${local.pubsub_topic_name}-dlq"
  project = var.project_id

  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# SECURITY LAYER
# ============================================================================

# Service account for Cloud Scheduler with minimal permissions
resource "google_service_account" "scheduler_sa" {
  account_id   = local.service_account_name
  display_name = "Video Moderation Scheduler Service Account"
  description  = "Service account for automated video moderation scheduling"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM policy binding for Pub/Sub publishing
resource "google_project_iam_member" "scheduler_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# IAM policy binding for Cloud Scheduler operations
resource "google_project_iam_member" "scheduler_job_runner" {
  project = var.project_id
  role    = "roles/cloudscheduler.jobRunner"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# IAM policy bindings for Cloud Function service account
resource "google_project_iam_member" "function_video_intelligence" {
  project = var.project_id
  role    = "roles/videointelligence.editor"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

# ============================================================================
# FUNCTION SOURCE CODE PREPARATION
# ============================================================================

# Create local directory for function source code
resource "null_resource" "prepare_function_source" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${local.function_source_dir}
      cat > ${local.function_source_dir}/main.py << 'EOF'
import json
import os
import logging
from google.cloud import videointelligence
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def video_moderation_handler(cloud_event):
    """
    Process video moderation requests triggered by Cloud Scheduler.
    Analyzes videos for explicit content using Video Intelligence API.
    """
    try:
        # Initialize clients
        video_client = videointelligence.VideoIntelligenceServiceClient()
        storage_client = storage.Client()
        
        # Parse message data
        message_data = json.loads(cloud_event.data.get('message', {}).get('data', '{}'))
        bucket_name = message_data.get('bucket', os.environ['BUCKET_NAME'])
        
        logger.info(f"Processing moderation for bucket: {bucket_name}")
        
        # List videos in processing folder
        bucket = storage_client.bucket(bucket_name)
        blobs = list(bucket.list_blobs(prefix='processing/'))
        
        processed_count = 0
        for blob in blobs:
            if blob.name.endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm', '.flv')):
                process_video(video_client, storage_client, bucket_name, blob.name)
                processed_count += 1
        
        logger.info(f"Video moderation batch processing completed. Processed {processed_count} videos.")
        
    except Exception as e:
        logger.error(f"Error in video moderation: {str(e)}")
        raise

def process_video(video_client, storage_client, bucket_name, video_path):
    """
    Analyze individual video for explicit content and take moderation action.
    """
    try:
        # Configure video analysis request
        gcs_uri = f"gs://{bucket_name}/{video_path}"
        features = [videointelligence.Feature.EXPLICIT_CONTENT_DETECTION]
        
        logger.info(f"Analyzing video: {gcs_uri}")
        
        # Submit video for analysis
        operation = video_client.annotate_video(
            request={
                "input_uri": gcs_uri,
                "features": features,
            }
        )
        
        # Wait for analysis completion
        result = operation.result(timeout=300)
        
        # Process explicit content detection results
        moderation_result = analyze_explicit_content(result)
        
        # Take moderation action based on analysis
        take_moderation_action(storage_client, bucket_name, video_path, moderation_result)
        
        logger.info(f"Video analysis completed: {video_path}")
        
    except Exception as e:
        logger.error(f"Error processing video {video_path}: {str(e)}")

def analyze_explicit_content(result):
    """
    Analyze explicit content detection results and determine moderation action.
    """
    explicit_annotation = result.annotation_results[0].explicit_annotation
    
    # Calculate overall confidence score
    total_frames = len(explicit_annotation.frames)
    if total_frames == 0:
        return {"action": "approve", "confidence": 0.0, "reason": "No frames analyzed"}
    
    # Get thresholds from environment variables
    threshold = int(os.environ.get('EXPLICIT_CONTENT_THRESHOLD', '3'))
    ratio_threshold = float(os.environ.get('EXPLICIT_CONTENT_RATIO_THRESHOLD', '0.1'))
    
    high_confidence_count = 0
    total_confidence = 0
    
    for frame in explicit_annotation.frames:
        confidence = frame.pornography_likelihood.value
        total_confidence += confidence
        
        # Count high-confidence explicit content frames
        if confidence >= threshold:
            high_confidence_count += 1
    
    average_confidence = total_confidence / total_frames
    explicit_ratio = high_confidence_count / total_frames
    
    # Determine moderation action
    if explicit_ratio > ratio_threshold or average_confidence > threshold:
        return {
            "action": "flag",
            "confidence": average_confidence,
            "explicit_ratio": explicit_ratio,
            "reason": f"High explicit content ratio: {explicit_ratio:.2%}"
        }
    else:
        return {
            "action": "approve",
            "confidence": average_confidence,
            "explicit_ratio": explicit_ratio,
            "reason": "Content within acceptable thresholds"
        }

def take_moderation_action(storage_client, bucket_name, video_path, moderation_result):
    """
    Move video to appropriate folder based on moderation result.
    """
    bucket = storage_client.bucket(bucket_name)
    source_blob = bucket.blob(video_path)
    
    # Determine target folder based on moderation action
    if moderation_result["action"] == "flag":
        target_path = video_path.replace("processing/", "flagged/")
    else:
        target_path = video_path.replace("processing/", "approved/")
    
    # Copy video to target folder
    target_blob = bucket.copy_blob(source_blob, bucket, target_path)
    
    # Delete original video from processing folder
    source_blob.delete()
    
    # Log moderation decision
    logger.info(f"Video moderation completed - Action: {moderation_result['action']}, "
                f"Confidence: {moderation_result['confidence']:.2f}, "
                f"Target: {target_path}")
EOF

      cat > ${local.function_source_dir}/requirements.txt << 'EOF'
google-cloud-videointelligence==2.13.3
google-cloud-storage==2.10.0
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    EOT
  }

  triggers = {
    # Trigger when function configuration changes
    function_memory     = var.function_memory
    function_timeout    = var.function_timeout
    bucket_name        = local.bucket_name
    content_threshold  = var.explicit_content_threshold
    ratio_threshold    = var.explicit_content_ratio_threshold
  }
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = "${path.module}/function-source.zip"
  
  depends_on = [null_resource.prepare_function_source]
}

# ============================================================================
# COMPUTE LAYER
# ============================================================================

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.bucket_name}-function-source"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true

  labels = merge(local.common_labels, {
    purpose = "function-source"
  })

  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function (Generation 2) for video processing
resource "google_cloudfunctions2_function" "video_moderator" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated video content moderation using Video Intelligence API"

  build_config {
    runtime     = "python311"
    entry_point = "video_moderation_handler"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    available_cpu         = var.function_cpu
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    # Environment variables for function configuration
    environment_variables = {
      BUCKET_NAME                      = google_storage_bucket.video_bucket.name
      EXPLICIT_CONTENT_THRESHOLD       = var.explicit_content_threshold
      EXPLICIT_CONTENT_RATIO_THRESHOLD = var.explicit_content_ratio_threshold
    }

    # Use default service account with appropriate permissions
    service_account_email = "${var.project_id}@appspot.gserviceaccount.com"
  }

  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.video_moderation.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_video_intelligence,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_logging_writer
  ]
}

# ============================================================================
# SCHEDULING LAYER
# ============================================================================

# Cloud Scheduler job for automated video moderation
resource "google_cloud_scheduler_job" "video_moderation_scheduler" {
  name        = local.scheduler_job_name
  description = "Automated trigger for video content moderation batch processing"
  schedule    = var.schedule_expression
  time_zone   = var.schedule_timezone
  region      = var.region
  project     = var.project_id

  # Pub/Sub target configuration
  pubsub_target {
    topic_name = google_pubsub_topic.video_moderation.id
    data = base64encode(jsonencode({
      bucket    = google_storage_bucket.video_bucket.name
      trigger   = "scheduled"
      timestamp = "$${CURRENT_TIMESTAMP}"
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.scheduler_sa,
    google_project_iam_member.scheduler_pubsub_publisher,
    google_project_iam_member.scheduler_job_runner
  ]
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

# Log sink for video moderation function logs
resource "google_logging_project_sink" "video_moderation_logs" {
  name        = "${local.function_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.video_bucket.name}"
  
  # Filter for video moderation function logs
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.video_moderator.name}\""
  
  # Unique writer identity for the sink
  unique_writer_identity = true
  
  depends_on = [google_cloudfunctions2_function.video_moderator]
}

# Grant storage write permissions to log sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.video_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.video_moderation_logs.writer_identity
}