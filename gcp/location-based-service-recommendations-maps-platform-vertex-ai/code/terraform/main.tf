# Location-Based Service Recommendations with Google Maps Platform and Vertex AI
# This configuration creates a complete serverless recommendation system using Cloud Run, Firestore, and AI services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    creation-date     = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Resource naming with random suffix
  service_name_unique    = "${var.service_name}-${random_id.suffix.hex}"
  database_name_unique   = "${var.database_name}-${random_id.suffix.hex}"
  api_key_name          = "maps-api-key-${random_id.suffix.hex}"
  service_account_name  = "location-ai-service-${random_id.suffix.hex}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "aiplatform.googleapis.com", 
    "firestore.googleapis.com",
    "maps-backend.googleapis.com",
    "places-backend.googleapis.com",
    "geocoding-backend.googleapis.com",
    "mapsgrounding.googleapis.com",
    "cloudbuild.googleapis.com",
    "vpcaccess.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for the recommendation service
resource "google_service_account" "location_ai_service" {
  account_id   = local.service_account_name
  display_name = "Location AI Recommendation Service"
  description  = "Service account for location-based AI recommendation system"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM permissions to the service account
resource "google_project_iam_member" "ai_platform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.location_ai_service.email}"
}

resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.location_ai_service.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.location_ai_service.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.location_ai_service.email}"
}

# Create Google Maps Platform API key with restrictions
resource "google_apikeys_key" "maps_api_key" {
  name         = local.api_key_name
  display_name = "Location Recommender API Key"
  project      = var.project_id
  
  restrictions {
    # API restrictions - limit to only required Maps Platform services
    api_targets {
      service = "maps-backend.googleapis.com"
    }
    api_targets {
      service = "places-backend.googleapis.com"
    }
    api_targets {
      service = "geocoding-backend.googleapis.com"
    }
    
    # Browser key restrictions (can be customized for production)
    browser_key_restrictions {
      allowed_referrers = ["*"] # Restrict this in production
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore database for user preferences and recommendation cache
resource "google_firestore_database" "recommendations_db" {
  project                     = var.project_id
  name                       = local.database_name_unique
  location_id                = var.firestore_location
  type                       = "FIRESTORE_NATIVE"
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  # Enable point-in-time recovery for production workloads
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = "DELETE_PROTECTION_DISABLED" # Set to ENABLED for production
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore composite indexes for efficient querying
resource "google_firestore_field" "user_preferences_index" {
  project    = var.project_id
  database   = google_firestore_database.recommendations_db.name
  collection = "user_preferences"
  field      = "userId"
  
  index_config {
    indexes {
      fields {
        field_path = "userId"
        order      = "ASCENDING"
      }
      fields {
        field_path = "lastUpdated"
        order      = "DESCENDING"
      }
      query_scope = "COLLECTION"
    }
  }
  
  depends_on = [google_firestore_database.recommendations_db]
}

resource "google_firestore_field" "recommendations_cache_index" {
  project    = var.project_id
  database   = google_firestore_database.recommendations_db.name
  collection = "recommendations_cache"
  field      = "locationHash"
  
  index_config {
    indexes {
      fields {
        field_path = "locationHash"
        order      = "ASCENDING"
      }
      fields {
        field_path = "timestamp"
        order      = "DESCENDING"
      }
      query_scope = "COLLECTION"
    }
  }
  
  depends_on = [google_firestore_database.recommendations_db]
}

# Optional: Create VPC connector for private network access
resource "google_vpc_access_connector" "cloud_run_connector" {
  count = var.enable_vpc_connector ? 1 : 0
  
  name           = "location-ai-connector-${random_id.suffix.hex}"
  project        = var.project_id
  region         = var.region
  ip_cidr_range  = "10.8.0.0/28"
  network        = "default"
  machine_type   = var.vpc_connector_machine_type
  min_instances  = 2
  max_instances  = 3
  
  depends_on = [google_project_service.required_apis]
}

# Deploy Cloud Run service for the recommendation API
resource "google_cloud_run_v2_service" "location_recommender" {
  name     = local.service_name_unique
  project  = var.project_id
  location = var.region
  
  labels = local.common_labels
  
  template {
    labels = local.common_labels
    
    # Service account and resource limits
    service_account = google_service_account.location_ai_service.email
    
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    
    # Optional VPC connector configuration
    dynamic "vpc_access" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        connector = google_vpc_access_connector.cloud_run_connector[0].id
        egress    = "ALL_TRAFFIC" # or "PRIVATE_RANGES_ONLY" for more security
      }
    }
    
    containers {
      # Container image will be built from source code
      image = "gcr.io/cloudrun/hello" # Placeholder - will be replaced during deployment
      
      ports {
        name           = "http1"
        container_port = var.container_port
      }
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }
      
      # Environment variables for the application
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "FIRESTORE_DATABASE"
        value = google_firestore_database.recommendations_db.name
      }
      
      env {
        name  = "MAPS_API_KEY"
        value = google_apikeys_key.maps_api_key.key_string
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "AI_MODEL_NAME"
        value = var.ai_model_name
      }
      
      env {
        name  = "ENABLE_MAPS_GROUNDING"
        value = tostring(var.enable_maps_grounding)
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/"
          port = var.container_port
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/"
          port = var.container_port
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
  }
  
  # Traffic configuration - 100% to latest revision
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.location_ai_service,
    google_firestore_database.recommendations_db,
    google_apikeys_key.maps_api_key
  ]
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to the container image as it will be updated via CI/CD
      template[0].containers[0].image
    ]
  }
}

# Configure Cloud Run IAM for public access (customize for production)
resource "google_cloud_run_service_iam_binding" "public_access" {
  project  = var.project_id
  location = google_cloud_run_v2_service.location_recommender.location
  service  = google_cloud_run_v2_service.location_recommender.name
  role     = "roles/run.invoker"
  
  members = [
    "allUsers" # Change to specific users/service accounts for production
  ]
}

# Enable audit logging for the project (optional)
resource "google_project_iam_audit_config" "audit_logs" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id
  
  audit_log_config {
    log_type         = "ADMIN_READ"
    exempted_members = []
  }
  
  audit_log_config {
    log_type         = "DATA_READ"
    exempted_members = []
  }
  
  audit_log_config {
    log_type         = "DATA_WRITE"
    exempted_members = []
  }
  
  service = "allServices"
}

# Create Cloud Logging sink for application logs (optional)
resource "google_logging_project_sink" "recommendation_logs" {
  name        = "location-ai-logs-${random_id.suffix.hex}"
  project     = var.project_id
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/location-recommendations"
  
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.location_recommender.name}\""
  
  unique_writer_identity = true
}

# Create monitoring alert policy for service health (optional)
resource "google_monitoring_alert_policy" "service_availability" {
  display_name = "Location Recommender Service Availability"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Run service not receiving traffic"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.location_recommender.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [] # Add notification channels as needed
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}