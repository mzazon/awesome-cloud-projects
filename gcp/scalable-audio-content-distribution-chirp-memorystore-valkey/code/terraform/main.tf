# Main Terraform configuration for scalable audio content distribution
# This infrastructure deploys a comprehensive audio generation and distribution platform
# using Google Cloud's Text-to-Speech API, Memorystore for Valkey, Cloud Storage, and CDN

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention for all resources
  name_prefix = "${var.resource_prefix}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Merged labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    created_by  = "terraform"
    project     = "audio-distribution"
  })
  
  # Network and subnet names
  network_name           = "${local.name_prefix}-network-${local.name_suffix}"
  memorystore_subnet_name = "${local.name_prefix}-memorystore-subnet-${local.name_suffix}"
  
  # Storage and CDN names
  bucket_name          = "${local.name_prefix}-audio-${local.name_suffix}"
  cdn_backend_name     = "${local.name_prefix}-backend-${local.name_suffix}"
  cdn_url_map_name     = "${local.name_prefix}-urlmap-${local.name_suffix}"
  cdn_proxy_name       = "${local.name_prefix}-proxy-${local.name_suffix}"
  cdn_forwarding_name  = "${local.name_prefix}-forwarding-${local.name_suffix}"
  cdn_ip_name          = "${local.name_prefix}-ip-${local.name_suffix}"
  
  # Memorystore names
  valkey_instance_name        = "${local.name_prefix}-valkey-${local.name_suffix}"
  service_connection_policy_name = "${local.name_prefix}-policy-${local.name_suffix}"
  
  # Compute and serverless names
  function_name    = "${local.name_prefix}-processor-${local.name_suffix}"
  cloudrun_name    = "${local.name_prefix}-management-${local.name_suffix}"
  
  # Service account names
  tts_service_account_name = "${local.name_prefix}-tts-sa-${local.name_suffix}"
  function_service_account_name = "${local.name_prefix}-func-sa-${local.name_suffix}"
  cloudrun_service_account_name = "${local.name_prefix}-run-sa-${local.name_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "enabled_apis" {
  for_each = toset(var.enable_apis)
  
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC network for the audio distribution platform
resource "google_compute_network" "audio_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  description            = "VPC network for scalable audio content distribution platform"
  
  depends_on = [google_project_service.enabled_apis]
}

# Create subnet for Memorystore connectivity
resource "google_compute_subnetwork" "memorystore_subnet" {
  name          = local.memorystore_subnet_name
  ip_cidr_range = var.memorystore_subnet_cidr
  region        = var.region
  network       = google_compute_network.audio_network.id
  description   = "Subnet for Memorystore Valkey instance connectivity"
  
  # Enable private Google access for API connectivity
  private_ip_google_access = true
}

# Create firewall rules for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal-${local.name_suffix}"
  network = google_compute_network.audio_network.name
  
  description = "Allow internal communication within the audio distribution network"
  
  allow {
    protocol = "tcp"
    ports    = ["6379", "8080", "443", "80"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.network_cidr]
  target_tags   = ["audio-distribution"]
}

# Create firewall rule for HTTP/HTTPS access
resource "google_compute_firewall" "allow_http_https" {
  name    = "${local.name_prefix}-allow-http-https-${local.name_suffix}"
  network = google_compute_network.audio_network.name
  
  description = "Allow HTTP and HTTPS access for web services"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}

# Service connection policy for Memorystore
resource "google_network_connectivity_service_connection_policy" "memorystore_policy" {
  name          = local.service_connection_policy_name
  location      = var.region
  service_class = "gcp-memorystore"
  description   = "Service connection policy for Memorystore Valkey instance"
  network       = google_compute_network.audio_network.id
  
  psc_config {
    subnetworks = [google_compute_subnetwork.memorystore_subnet.id]
  }
  
  depends_on = [google_project_service.enabled_apis]
}

# Memorystore for Valkey instance for high-performance caching
resource "google_memorystore_instance" "valkey_cache" {
  instance_id                 = local.valkey_instance_name
  location                   = var.region
  shard_count                = var.valkey_shard_count
  replica_count              = var.valkey_replica_count
  node_type                  = var.valkey_node_type
  deletion_protection_enabled = false
  
  # Authentication and encryption settings
  authorization_mode      = var.enable_valkey_auth ? "IAM_AUTH" : "AUTH_DISABLED"
  transit_encryption_mode = var.enable_valkey_encryption ? "SERVER_AUTHENTICATION" : "TRANSIT_ENCRYPTION_DISABLED"
  
  # Engine configuration for optimal audio caching
  engine_configs = {
    maxmemory-policy = "allkeys-lru"
    timeout          = "300"
    tcp-keepalive    = "60"
  }
  
  # Zone distribution for high availability
  zone_distribution_config {
    mode = var.valkey_replica_count > 0 ? "MULTI_ZONE" : "SINGLE_ZONE"
    zone = var.valkey_replica_count == 0 ? var.zone : null
  }
  
  # Maintenance window configuration
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
  
  # Persistence configuration for data durability
  persistence_config {
    mode = "RDB"
    rdb_config {
      rdb_snapshot_period     = "ONE_HOUR"
      rdb_snapshot_start_time = "2024-01-01T02:00:00Z"
    }
  }
  
  # Automated backups for disaster recovery
  automated_backup_config {
    retention = "604800s"  # 7 days
    fixed_frequency_schedule {
      start_time {
        hours = 3
      }
    }
  }
  
  # Network endpoint configuration
  desired_auto_created_endpoints {
    network    = google_compute_network.audio_network.id
    project_id = var.project_id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_network_connectivity_service_connection_policy.memorystore_policy,
    google_project_service.enabled_apis
  ]
  
  lifecycle {
    prevent_destroy = false
  }
}

# Cloud Storage bucket for audio asset storage
resource "google_storage_bucket" "audio_bucket" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.storage_class
  
  # Prevent accidental deletion
  force_destroy = false
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Public access prevention
  public_access_prevention = "inherited"
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
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
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = var.cors_methods
    response_header = var.cors_response_headers
    max_age_seconds = var.cors_max_age_seconds
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.enabled_apis]
}

# IAM binding to make bucket publicly readable
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.audio_bucket.name
  role   = "roles/storage.legacyObjectReader"
  member = "allUsers"
}

# Service account for Text-to-Speech operations
resource "google_service_account" "tts_service_account" {
  account_id   = local.tts_service_account_name
  display_name = "Text-to-Speech Service Account"
  description  = "Service account for Text-to-Speech API operations in audio distribution platform"
  
  depends_on = [google_project_service.enabled_apis]
}

# IAM bindings for Text-to-Speech service account
resource "google_project_iam_member" "tts_user" {
  project = var.project_id
  role    = "roles/cloudtts.user"
  member  = "serviceAccount:${google_service_account.tts_service_account.email}"
}

resource "google_project_iam_member" "tts_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.tts_service_account.email}"
}

# Service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = local.function_service_account_name
  display_name = "Audio Processor Function Service Account"
  description  = "Service account for Cloud Functions in audio distribution platform"
  
  depends_on = [google_project_service.enabled_apis]
}

# IAM bindings for Cloud Functions service account
resource "google_project_iam_member" "function_tts_user" {
  project = var.project_id
  role    = "roles/cloudtts.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_memorystore_user" {
  project = var.project_id
  role    = "roles/memcache.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Functions source code archive
resource "google_storage_bucket_object" "function_source" {
  name   = "audio-processor-function-${local.name_suffix}.zip"
  bucket = google_storage_bucket.audio_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [google_storage_bucket.audio_bucket]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/audio-processor-function-${local.name_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/index.js", {
      bucket_name = google_storage_bucket.audio_bucket.name
      valkey_host = google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
      valkey_port = "6379"
    })
    filename = "index.js"
  }
  
  source {
    content = file("${path.module}/function_code/package.json")
    filename = "package.json"
  }
}

# Cloud Function for audio processing
resource "google_cloudfunctions2_function" "audio_processor" {
  name        = local.function_name
  location    = var.region
  description = "Processes audio generation requests with Text-to-Speech and caching"
  
  build_config {
    runtime     = "nodejs18"
    entry_point = "processAudio"
    
    source {
      storage_source {
        bucket = google_storage_bucket.audio_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.audio_bucket.name
      VALKEY_HOST = google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
      VALKEY_PORT = "6379"
      PROJECT_ID  = var.project_id
    }
    
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.enabled_apis,
    google_storage_bucket_object.function_source,
    google_memorystore_instance.valkey_cache
  ]
}

# IAM binding to allow unauthenticated invocation of the function
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.audio_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Service account for Cloud Run
resource "google_service_account" "cloudrun_service_account" {
  account_id   = local.cloudrun_service_account_name
  display_name = "Audio Management Cloud Run Service Account"
  description  = "Service account for Cloud Run services in audio distribution platform"
  
  depends_on = [google_project_service.enabled_apis]
}

# IAM bindings for Cloud Run service account
resource "google_project_iam_member" "cloudrun_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.cloudrun_service_account.email}"
}

resource "google_project_iam_member" "cloudrun_memorystore_user" {
  project = var.project_id
  role    = "roles/memcache.user"
  member  = "serviceAccount:${google_service_account.cloudrun_service_account.email}"
}

# Cloud Run service for audio management API
resource "google_cloud_run_v2_service" "audio_management" {
  name     = local.cloudrun_name
  location = var.region
  
  template {
    service_account = google_service_account.cloudrun_service_account.email
    
    scaling {
      min_instance_count = var.cloudrun_min_instances
      max_instance_count = var.cloudrun_max_instances
    }
    
    containers {
      image = "gcr.io/cloudrun/hello"  # Placeholder image - replace with actual image
      
      resources {
        limits = {
          cpu    = var.cloudrun_cpu
          memory = var.cloudrun_memory
        }
      }
      
      env {
        name  = "FUNCTION_URL"
        value = google_cloudfunctions2_function.audio_processor.service_config[0].uri
      }
      
      env {
        name  = "VALKEY_HOST"
        value = google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
      }
      
      env {
        name  = "CDN_ENDPOINT"
        value = google_compute_global_address.cdn_ip.address
      }
      
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      ports {
        container_port = 8080
      }
    }
    
    vpc_access {
      network_interfaces {
        network    = google_compute_network.audio_network.id
        subnetwork = google_compute_subnetwork.memorystore_subnet.id
      }
      egress = "PRIVATE_RANGES_ONLY"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.enabled_apis,
    google_cloudfunctions2_function.audio_processor,
    google_memorystore_instance.valkey_cache
  ]
}

# IAM binding to allow unauthenticated access to Cloud Run service
resource "google_cloud_run_service_iam_member" "cloudrun_invoker" {
  location = google_cloud_run_v2_service.audio_management.location
  service  = google_cloud_run_v2_service.audio_management.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Global static IP address for CDN
resource "google_compute_global_address" "cdn_ip" {
  name        = local.cdn_ip_name
  description = "Global static IP address for audio content CDN"
  
  depends_on = [google_project_service.enabled_apis]
}

# Backend bucket for CDN
resource "google_compute_backend_bucket" "audio_backend" {
  name        = local.cdn_backend_name
  bucket_name = google_storage_bucket.audio_bucket.name
  description = "Backend bucket for audio content CDN"
  
  # CDN configuration for optimal audio delivery
  cdn_policy {
    cache_mode        = var.cdn_cache_mode
    default_ttl       = var.cdn_default_ttl
    max_ttl           = var.cdn_max_ttl
    client_ttl        = var.cdn_client_ttl
    negative_caching  = true
    
    # Cache key policy for audio content
    cache_key_policy {
      include_protocol     = false
      include_host         = false
      include_query_string = true
      query_string_whitelist = ["voice", "lang", "format"]
    }
    
    # Negative caching for error responses
    negative_caching_policy {
      code = 404
      ttl  = 120
    }
    
    negative_caching_policy {
      code = 500
      ttl  = 30
    }
  }
  
  depends_on = [google_storage_bucket.audio_bucket]
}

# URL map for CDN routing
resource "google_compute_url_map" "audio_cdn_map" {
  name            = local.cdn_url_map_name
  description     = "URL map for audio content CDN routing"
  default_service = google_compute_backend_bucket.audio_backend.id
  
  # Host rule for audio content
  host_rule {
    hosts        = ["*"]
    path_matcher = "audio-content"
  }
  
  path_matcher {
    name            = "audio-content"
    default_service = google_compute_backend_bucket.audio_backend.id
    
    # Route for generated audio files
    path_rule {
      paths   = ["/generated-audio/*"]
      service = google_compute_backend_bucket.audio_backend.id
    }
    
    # Route for cached content
    path_rule {
      paths   = ["/cache/*"]
      service = google_compute_backend_bucket.audio_backend.id
    }
  }
}

# HTTPS target proxy for CDN
resource "google_compute_target_https_proxy" "audio_https_proxy" {
  name    = local.cdn_proxy_name
  url_map = google_compute_url_map.audio_cdn_map.id
  
  # SSL certificate (placeholder - replace with actual certificate)
  ssl_certificates = [google_compute_managed_ssl_certificate.audio_ssl_cert.id]
}

# Managed SSL certificate for CDN
resource "google_compute_managed_ssl_certificate" "audio_ssl_cert" {
  name = "${local.name_prefix}-ssl-cert-${local.name_suffix}"
  
  managed {
    domains = ["${local.name_prefix}.example.com"]  # Replace with actual domain
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "audio_https_forwarding" {
  name       = "${local.cdn_forwarding_name}-https"
  target     = google_compute_target_https_proxy.audio_https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.cdn_ip.address
}

# HTTP target proxy for redirecting to HTTPS
resource "google_compute_target_http_proxy" "audio_http_proxy" {
  name    = "${local.cdn_proxy_name}-http"
  url_map = google_compute_url_map.https_redirect.id
}

# URL map for HTTPS redirect
resource "google_compute_url_map" "https_redirect" {
  name = "${local.cdn_url_map_name}-redirect"
  
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Global forwarding rule for HTTP traffic (redirects to HTTPS)
resource "google_compute_global_forwarding_rule" "audio_http_forwarding" {
  name       = "${local.cdn_forwarding_name}-http"
  target     = google_compute_target_http_proxy.audio_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.cdn_ip.address
}

# Cloud Monitoring dashboard for the audio distribution platform
resource "google_monitoring_dashboard" "audio_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Audio Distribution Platform Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Function Invocations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.audio_processor.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Memorystore Cache Hit Ratio"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"memorystore_instance\" resource.label.instance_id=\"${google_memorystore_instance.valkey_cache.instance_id}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.enabled_apis]
}

# Cloud Logging sink for audit logs
resource "google_logging_project_sink" "audio_audit_sink" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${local.name_prefix}-audit-sink-${local.name_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.audio_bucket.name}/logs"
  
  filter = "protoPayload.serviceName=\"texttospeech.googleapis.com\" OR protoPayload.serviceName=\"memcache.googleapis.com\" OR protoPayload.serviceName=\"storage.googleapis.com\""
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.enabled_apis]
}

# IAM binding for logging sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.audio_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audio_audit_sink[0].writer_identity
}