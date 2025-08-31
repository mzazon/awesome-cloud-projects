# Main Terraform configuration for GCP Real-time Video Collaboration with WebRTC and Cloud Run

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  resource_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
  })
  
  # Firestore database ID
  firestore_database_id = "video-rooms-${local.resource_suffix}"
  
  # Environment variables for Cloud Run
  default_env_vars = {
    FIRESTORE_DATABASE = local.firestore_database_id
    NODE_ENV          = "production"
    PORT              = tostring(var.container_port)
  }
  
  # Merge user-provided environment variables with defaults
  container_env_vars = merge(local.default_env_vars, var.environment_variables)
}

# Enable required Google Cloud APIs
resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"
  
  disable_on_destroy = false
}

resource "google_project_service" "firestore_api" {
  service = "firestore.googleapis.com"
  
  disable_on_destroy = false
}

resource "google_project_service" "cloud_build_api" {
  service = "cloudbuild.googleapis.com"
  
  disable_on_destroy = false
}

resource "google_project_service" "iap_api" {
  count   = var.enable_iap ? 1 : 0
  service = "iap.googleapis.com"
  
  disable_on_destroy = false
}

# Create Firestore database for real-time room management
resource "google_firestore_database" "video_rooms" {
  name        = local.firestore_database_id
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  # Enable point-in-time recovery for production workloads
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # Configure deletion protection
  deletion_policy = var.enable_deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  
  depends_on = [google_project_service.firestore_api]
}

# Create service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "webrtc-signaling-${local.resource_suffix}"
  display_name = "WebRTC Signaling Server Service Account"
  description  = "Service account for WebRTC signaling Cloud Run service"
}

# Grant Firestore access to the service account
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Grant Cloud Run invoker access for IAP (if enabled)
resource "google_project_iam_member" "run_invoker" {
  count   = var.enable_iap ? 1 : 0
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Deploy Cloud Run service for WebRTC signaling server
resource "google_cloud_run_v2_service" "webrtc_signaling" {
  name     = "${var.service_name}-${local.resource_suffix}"
  location = var.region
  
  # Deletion protection can be enabled for production environments
  deletion_protection = var.enable_deletion_protection
  
  template {
    # Configure scaling
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    
    # Service account configuration
    service_account = google_service_account.cloud_run_sa.email
    
    containers {
      # Container image - in production, this would be your built image
      image = var.container_image
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = true
        startup_cpu_boost = true
      }
      
      # Port configuration
      ports {
        container_port = var.container_port
        name          = "http1"
      }
      
      # Environment variables
      dynamic "env" {
        for_each = local.container_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = var.container_port
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    # Execution environment configuration
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Session affinity for WebSocket connections
    session_affinity = true
    
    # Timeout configuration
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.cloud_run_api,
    google_firestore_database.video_rooms
  ]
}

# Configure IAM policy for Cloud Run service
resource "google_cloud_run_service_iam_policy" "noauth" {
  count = var.enable_iap ? 0 : 1
  
  location = google_cloud_run_v2_service.webrtc_signaling.location
  project  = google_cloud_run_v2_service.webrtc_signaling.project
  service  = google_cloud_run_v2_service.webrtc_signaling.name
  
  policy_data = data.google_iam_policy.noauth[0].policy_data
}

# IAM policy data for unauthenticated access (when IAP is disabled)
data "google_iam_policy" "noauth" {
  count = var.enable_iap ? 0 : 1
  
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Configure Identity-Aware Proxy (if enabled)
resource "google_iap_web_iam_binding" "iap_users" {
  count = var.enable_iap && length(var.authorized_users) > 0 ? 1 : 0
  
  project = var.project_id
  role    = "roles/iap.httpsResourceAccessor"
  members = [for email in var.authorized_users : "user:${email}"]
  
  depends_on = [google_project_service.iap_api]
}

# Create Cloud Armor security policy for additional protection
resource "google_compute_security_policy" "webrtc_security_policy" {
  name        = "webrtc-security-policy-${local.resource_suffix}"
  description = "Security policy for WebRTC signaling server"
  
  # Default rule - allow all traffic (customize as needed)
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
  
  # Rate limiting rule
  rule {
    action   = "throttle"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    description = "Rate limiting rule: 100 requests per minute per IP"
  }
  
  # Block known bad IPs (example)
  rule {
    action   = "deny(403)"
    priority = "500"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = [
          # Add known malicious IP ranges here
          # "192.0.2.0/24",
        ]
      }
    }
    description = "Block known malicious IPs"
  }
  
  # Adaptive protection for DDoS mitigation
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# Create Cloud Run domain mapping (optional, for custom domain)
# Uncomment and configure if you want to use a custom domain
# resource "google_cloud_run_domain_mapping" "webrtc_domain" {
#   location = var.region
#   name     = "your-domain.com"
#   
#   metadata {
#     namespace = var.project_id
#   }
#   
#   spec {
#     route_name = google_cloud_run_v2_service.webrtc_signaling.name
#   }
# }

# Create monitoring alert policy for Cloud Run service health
resource "google_monitoring_alert_policy" "cloud_run_health" {
  display_name = "WebRTC Signaling Service Health"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Run Service Down"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.webrtc_signaling.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  notification_channels = []  # Add notification channels if needed
  
  alert_strategy {
    auto_close = "1800s"
  }
}