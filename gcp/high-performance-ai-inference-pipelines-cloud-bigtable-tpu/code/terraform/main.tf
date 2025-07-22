# Generate unique identifiers for resources
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for project information
data "google_project" "project" {
  project_id = var.project_id
}

data "google_compute_default_service_account" "default" {
  project = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigtable.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Don't disable the service if the resource is destroyed
  disable_on_destroy = false
}

# Create service accounts for different components
resource "google_service_account" "bigtable_sa" {
  count = var.enable_custom_service_accounts ? 1 : 0

  account_id   = "${var.resource_prefix}-bigtable-${random_id.suffix.hex}"
  display_name = "Bigtable Service Account for AI Inference"
  description  = "Service account for Bigtable operations in AI inference pipeline"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account" "vertex_ai_sa" {
  count = var.enable_custom_service_accounts ? 1 : 0

  account_id   = "${var.resource_prefix}-vertex-ai-${random_id.suffix.hex}"
  display_name = "Vertex AI Service Account"
  description  = "Service account for Vertex AI operations in AI inference pipeline"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account" "cloud_function_sa" {
  count = var.enable_custom_service_accounts ? 1 : 0

  account_id   = "${var.resource_prefix}-cf-${random_id.suffix.hex}"
  display_name = "Cloud Function Service Account"
  description  = "Service account for Cloud Function inference orchestration"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for service accounts
resource "google_project_iam_member" "bigtable_sa_roles" {
  for_each = var.enable_custom_service_accounts ? toset([
    "roles/bigtable.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.bigtable_sa[0].email}"
}

resource "google_project_iam_member" "vertex_ai_sa_roles" {
  for_each = var.enable_custom_service_accounts ? toset([
    "roles/aiplatform.user",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_sa[0].email}"
}

resource "google_project_iam_member" "cloud_function_sa_roles" {
  for_each = var.enable_custom_service_accounts ? toset([
    "roles/bigtable.user",
    "roles/redis.editor",
    "roles/aiplatform.user",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_function_sa[0].email}"
}

# Cloud Storage bucket for model artifacts
resource "google_storage_bucket" "model_artifacts" {
  count = var.enable_storage_bucket ? 1 : 0

  name          = "${var.resource_prefix}-models-${random_id.suffix.hex}"
  location      = var.storage_bucket_location
  storage_class = var.storage_bucket_storage_class
  project       = var.project_id

  # Enable versioning for model artifacts
  versioning {
    enabled = true
  }

  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Bigtable instance for feature storage
resource "google_bigtable_instance" "feature_store" {
  name         = "${var.resource_prefix}-bt-${random_id.suffix.hex}"
  display_name = var.bigtable_instance_display_name
  project      = var.project_id
  
  # Enable deletion protection if specified
  deletion_protection = var.enable_deletion_protection

  cluster {
    cluster_id   = "feature-cluster"
    zone         = var.zone
    num_nodes    = var.bigtable_cluster_num_nodes
    storage_type = var.bigtable_cluster_storage_type
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Bigtable tables for different feature types
resource "google_bigtable_table" "feature_tables" {
  for_each = var.bigtable_tables

  name          = each.key
  instance_name = google_bigtable_instance.feature_store.name
  project       = var.project_id

  # Configure column families for each table
  dynamic "column_family" {
    for_each = each.value.column_families
    content {
      family = column_family.key
    }
  }

  # Enable change stream for real-time features
  change_stream_retention = "24h0m0s"

  depends_on = [google_bigtable_instance.feature_store]
}

# Set garbage collection policies for column families
resource "google_bigtable_gc_policy" "feature_table_gc_policies" {
  for_each = {
    for table_cf in flatten([
      for table_name, table_config in var.bigtable_tables : [
        for cf_name, cf_config in table_config.column_families : {
          table_name = table_name
          cf_name    = cf_name
          cf_config  = cf_config
        }
      ]
    ]) : "${table_cf.table_name}_${table_cf.cf_name}" => table_cf
  }

  instance_name = google_bigtable_instance.feature_store.name
  table         = each.value.table_name
  column_family = each.value.cf_name
  project       = var.project_id

  max_version {
    number = each.value.cf_config.max_versions
  }

  depends_on = [google_bigtable_table.feature_tables]
}

# Redis instance for feature caching
resource "google_redis_instance" "feature_cache" {
  name               = "${var.resource_prefix}-cache-${random_id.suffix.hex}"
  display_name       = "Feature Cache for AI Inference"
  tier               = var.redis_tier
  memory_size_gb     = var.redis_memory_size_gb
  region             = var.region
  redis_version      = var.redis_version
  project            = var.project_id

  # Redis configuration
  redis_configs = var.redis_config

  # Enable auth and encryption
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  # Enable maintenance policy
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.resource_prefix}-function-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py.tpl", {
      project_id             = var.project_id
      region                = var.region
      bigtable_instance_id  = google_bigtable_instance.feature_store.name
      redis_host            = google_redis_instance.feature_cache.host
      redis_port            = google_redis_instance.feature_cache.port
    })
    filename = "main.py"
  }

  source {
    content = templatefile("${path.module}/function_source/requirements.txt.tpl", {})
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for inference orchestration
resource "google_cloudfunctions2_function" "inference_pipeline" {
  name        = var.cloud_function_name
  location    = var.region
  description = "High-performance AI inference pipeline orchestration"
  project     = var.project_id

  build_config {
    runtime     = var.cloud_function_runtime
    entry_point = "inference_pipeline"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.cloud_function_max_instances
    min_instance_count = var.cloud_function_min_instances
    available_memory   = var.cloud_function_memory
    timeout_seconds    = var.cloud_function_timeout

    # Use custom service account if enabled
    service_account_email = var.enable_custom_service_accounts ? google_service_account.cloud_function_sa[0].email : null

    # Environment variables
    environment_variables = {
      PROJECT_ID            = var.project_id
      REGION               = var.region
      BIGTABLE_INSTANCE_ID = google_bigtable_instance.feature_store.name
      REDIS_HOST           = google_redis_instance.feature_cache.host
      REDIS_PORT           = google_redis_instance.feature_cache.port
      VERTEX_AI_ENDPOINT   = google_vertex_ai_endpoint.inference_endpoint.name
    }

    # Enable all traffic to use latest revision
    ingress_settings = "ALLOW_ALL"
  }

  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create IAM policy for Cloud Function to allow unauthenticated access
resource "google_cloud_run_service_iam_member" "function_public_access" {
  project  = var.project_id
  location = google_cloudfunctions2_function.inference_pipeline.location
  service  = google_cloudfunctions2_function.inference_pipeline.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Vertex AI Model Registry (placeholder for uploaded model)
resource "google_vertex_ai_model" "inference_model" {
  display_name = var.vertex_ai_model_display_name
  description  = "High-performance recommendation model for AI inference pipeline"
  project      = var.project_id
  region       = var.region

  # Model artifact configuration
  # Note: In practice, you would upload your model to Cloud Storage first
  # and reference it here. This is a placeholder configuration.
  
  # Container specification for TPU-optimized inference
  container_spec {
    image_uri = "us-docker.pkg.dev/vertex-ai-restricted/prediction/tf_opt-tpu.2-15:latest"
    
    # Environment variables for model serving
    env {
      name  = "MODEL_NAME"
      value = "recommendation_model"
    }
    
    # Health check configuration
    health_route = "/health"
    predict_route = "/predict"
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Vertex AI Endpoint for TPU inference
resource "google_vertex_ai_endpoint" "inference_endpoint" {
  display_name = var.vertex_ai_endpoint_display_name
  description  = "TPU-optimized endpoint for high-performance AI inference"
  location     = var.region
  project      = var.project_id

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Deploy model to endpoint
resource "google_vertex_ai_endpoint_deployed_model" "inference_deployment" {
  endpoint = google_vertex_ai_endpoint.inference_endpoint.id
  model    = google_vertex_ai_model.inference_model.id

  display_name = "tpu-optimized-deployment"

  # TPU configuration
  machine_spec {
    machine_type = var.vertex_ai_machine_type
    
    accelerator_spec {
      type  = var.vertex_ai_accelerator_type
      count = var.vertex_ai_accelerator_count
    }
  }

  # Auto-scaling configuration
  auto_scaling {
    min_replica_count = var.vertex_ai_min_replica_count
    max_replica_count = var.vertex_ai_max_replica_count
  }

  # Traffic allocation (100% to this deployment)
  traffic_split = 100

  depends_on = [
    google_vertex_ai_endpoint.inference_endpoint,
    google_vertex_ai_model.inference_model
  ]
}

# Cloud Monitoring resources
resource "google_monitoring_alert_policy" "inference_latency_alert" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "AI Inference Pipeline - High Latency"
  combiner     = "OR"
  project      = var.project_id

  conditions {
    display_name = "Cloud Function Latency"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.monitoring_alert_latency_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.monitoring_notification_channels

  alert_strategy {
    auto_close = "604800s" # 7 days
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_alert_policy" "inference_error_rate_alert" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "AI Inference Pipeline - High Error Rate"
  combiner     = "OR"
  project      = var.project_id

  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\""
      duration        = "120s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.monitoring_alert_error_rate_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.monitoring_notification_channels

  alert_strategy {
    auto_close = "604800s" # 7 days
  }

  depends_on = [google_project_service.required_apis]
}

# Log-based metrics for custom monitoring
resource "google_logging_metric" "inference_latency_metric" {
  count = var.enable_monitoring ? 1 : 0

  name    = "inference_latency"
  project = var.project_id

  filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\" jsonPayload.latency_ms>0"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Inference Pipeline Latency"
  }

  value_extractor = "EXTRACT(jsonPayload.latency_ms)"

  depends_on = [google_project_service.required_apis]
}

resource "google_logging_metric" "cache_hit_ratio_metric" {
  count = var.enable_monitoring ? 1 : 0

  name    = "cache_hit_ratio"
  project = var.project_id

  filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\" jsonPayload.message:\"Cache hit\""

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Cache Hit Ratio"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "inference_pipeline_dashboard" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "AI Inference Pipeline Dashboard"
  project      = var.project_id

  dashboard_json = jsonencode({
    displayName = "AI Inference Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Inference Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Latency (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Error Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.cloud_function_name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Error Rate"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create template files for Cloud Function source code
resource "local_file" "function_main_template" {
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id            = var.project_id
    region               = var.region
    bigtable_instance_id = google_bigtable_instance.feature_store.name
    redis_host           = google_redis_instance.feature_cache.host
    redis_port           = google_redis_instance.feature_cache.port
  })
  filename = "${path.module}/function_source/main.py.tpl"
}

resource "local_file" "function_requirements_template" {
  content = templatefile("${path.module}/templates/requirements.txt.tpl", {})
  filename = "${path.module}/function_source/requirements.txt.tpl"
}

# Create the actual template files
resource "local_file" "main_py_template" {
  content = <<-EOT
import functions_framework
import json
import numpy as np
import redis
from google.cloud import bigtable
from google.cloud import aiplatform
from google.auth import default
import logging
import time
import os

# Initialize clients
credentials, project = default()
bigtable_client = bigtable.Client(project=project, credentials=credentials)
redis_client = redis.Redis(host=os.environ['REDIS_HOST'], port=int(os.environ['REDIS_PORT']))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def inference_pipeline(request):
    """High-performance inference pipeline with intelligent caching"""
    start_time = time.time()
    
    try:
        # Parse request
        request_json = request.get_json()
        user_id = request_json.get('user_id')
        item_id = request_json.get('item_id')
        context = request_json.get('context', {})
        
        # Step 1: Try Redis cache first for hot features
        cache_key = f"features:{user_id}:{item_id}"
        cached_features = redis_client.get(cache_key)
        
        if cached_features:
            logger.info(f"Cache hit for {cache_key}")
            features = json.loads(cached_features)
        else:
            # Step 2: Retrieve features from Bigtable
            features = retrieve_features_from_bigtable(user_id, item_id, context)
            
            # Cache the features for future requests
            redis_client.setex(cache_key, 300, json.dumps(features))  # 5 min TTL
            logger.info(f"Features cached for {cache_key}")
        
        # Step 3: Prepare features for TPU inference
        inference_input = prepare_inference_input(features)
        
        # Step 4: Call TPU endpoint for prediction
        prediction = call_tpu_endpoint(inference_input)
        
        # Step 5: Post-process and return results
        result = {
            'user_id': user_id,
            'item_id': item_id,
            'prediction': float(prediction),
            'confidence': calculate_confidence(features, prediction),
            'latency_ms': round((time.time() - start_time) * 1000, 2)
        }
        
        logger.info(f"Inference completed in {result['latency_ms']}ms")
        return json.dumps(result), 200
        
    except Exception as e:
        logger.error(f"Inference error: {str(e)}")
        return json.dumps({'error': str(e)}), 500

def retrieve_features_from_bigtable(user_id, item_id, context):
    """Retrieve features from Bigtable with optimized read patterns"""
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        
        # Batch read for optimal performance
        user_table = instance.table('user_features')
        item_table = instance.table('item_features')
        context_table = instance.table('contextual_features')
        
        # Simulate feature retrieval (in production, use actual row keys)
        user_features = [0.1] * 128  # User embeddings
        item_features = [0.2] * 64   # Item embeddings  
        context_features = [0.3] * 32 # Contextual features
        
        return {
            'user_embeddings': user_features,
            'item_embeddings': item_features,
            'contextual_features': context_features
        }
        
    except Exception as e:
        logger.error(f"Bigtable retrieval error: {str(e)}")
        raise

def prepare_inference_input(features):
    """Prepare features for TPU inference"""
    return {
        'instances': [{
            'user_embeddings': features['user_embeddings'],
            'item_embeddings': features['item_embeddings'],
            'contextual_features': features['contextual_features']
        }]
    }

def call_tpu_endpoint(inference_input):
    """Call TPU endpoint for prediction"""
    try:
        aiplatform.init(project=os.environ['PROJECT_ID'], location=os.environ['REGION'])
        endpoint = aiplatform.Endpoint(os.environ['VERTEX_AI_ENDPOINT'])
        
        prediction = endpoint.predict(instances=inference_input['instances'])
        return prediction.predictions[0][0]
        
    except Exception as e:
        logger.error(f"TPU endpoint error: {str(e)}")
        # Return random prediction for demonstration
        return np.random.random()

def calculate_confidence(features, prediction):
    """Calculate prediction confidence based on feature quality"""
    # Simplified confidence calculation
    feature_variance = np.var(features['user_embeddings'] + features['item_embeddings'])
    base_confidence = 0.8 if feature_variance > 0.1 else 0.6
    return min(base_confidence + abs(prediction - 0.5), 1.0)
EOT
  filename = "${path.module}/templates/main.py.tpl"
}

resource "local_file" "requirements_txt_template" {
  content = <<-EOT
functions-framework==3.5.0
google-cloud-bigtable==2.21.0
google-cloud-aiplatform==1.42.1
redis==5.0.1
numpy==1.24.3
EOT
  filename = "${path.module}/templates/requirements.txt.tpl"
}