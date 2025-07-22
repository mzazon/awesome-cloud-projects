# Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache
# 
# This Terraform configuration deploys a comprehensive global content delivery solution
# leveraging Google Cloud WAN's planet-scale network infrastructure, Anywhere Cache for
# regional performance optimization, and Cloud CDN for global edge caching.
#
# Recipe: Establishing Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache
# Provider: Google Cloud Platform
# Services: Cloud WAN, Cloud Storage, Cloud Monitoring, Cloud CDN, Compute Engine

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com", 
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "networkconnectivity.googleapis.com"
  ])

  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Multi-region Cloud Storage bucket for global content distribution
resource "google_storage_bucket" "global_content_bucket" {
  name          = "global-content-${random_id.suffix.hex}"
  project       = var.project_id
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  force_destroy = var.force_destroy_bucket

  # Enable versioning for content protection and rollback capabilities
  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_storage_class == "STANDARD" ? [1] : []
    content {
      condition {
        age = 30
        with_state = "ARCHIVED"
      }
      action {
        type = "Delete"
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.bucket_storage_class == "STANDARD" ? [1] : []
    content {
      condition {
        age = 365
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }

  # Enable uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = var.enable_uniform_bucket_access

  # Configure public access prevention
  public_access_prevention = var.enable_public_access ? "inherited" : "enforced"

  # Apply consistent labeling for resource management
  labels = {
    purpose     = "global-content-delivery"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
    owner       = var.owner
    cost_center = var.cost_center
  }

  depends_on = [google_project_service.required_apis]
}

# Optional IAM binding for public read access (use with caution)
resource "google_storage_bucket_iam_member" "public_access" {
  count  = var.enable_public_access ? 1 : 0
  bucket = google_storage_bucket.global_content_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Sample content objects for testing (optional)
resource "google_storage_bucket_object" "sample_index" {
  count  = var.create_sample_content ? 1 : 0
  name   = "index.html"
  bucket = google_storage_bucket.global_content_bucket.name
  content = templatefile("${path.module}/sample-content/index.html.tpl", {
    bucket_name   = google_storage_bucket.global_content_bucket.name
    timestamp     = timestamp()
    environment   = var.environment
  })
  content_type = "text/html"
}

resource "google_storage_bucket_object" "sample_files" {
  for_each = var.create_sample_content ? {
    "small-file.dat"  = "1M"
    "medium-file.dat" = "10M"
    "large-file.dat"  = "100M"
  } : {}

  name   = each.key
  bucket = google_storage_bucket.global_content_bucket.name
  source = "/dev/urandom"
  
  # Note: In production, you would upload actual files
  # This is a placeholder for demonstration
  content = "Sample content for ${each.key} - ${each.value} equivalent"
}

# Cloud WAN Hub for enterprise networking backbone
resource "google_network_connectivity_hub" "enterprise_wan_hub" {
  name        = "enterprise-wan-${random_id.suffix.hex}"
  project     = var.project_id
  description = "Global content delivery WAN hub leveraging Google's backbone infrastructure"

  labels = {
    purpose     = "global-content-delivery"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
    owner       = var.owner
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud WAN Spokes for multi-region connectivity
resource "google_network_connectivity_spoke" "primary_spoke" {
  name        = "primary-spoke-${random_id.suffix.hex}"
  project     = var.project_id
  location    = var.primary_region
  hub         = google_network_connectivity_hub.enterprise_wan_hub.id
  description = "Primary region spoke for ${var.primary_region}"

  labels = {
    purpose     = "global-content-delivery"
    region      = "primary"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
  }
}

resource "google_network_connectivity_spoke" "secondary_spoke" {
  name        = "secondary-spoke-${random_id.suffix.hex}"
  project     = var.project_id
  location    = var.secondary_region
  hub         = google_network_connectivity_hub.enterprise_wan_hub.id
  description = "Secondary region spoke for ${var.secondary_region}"

  labels = {
    purpose     = "global-content-delivery"
    region      = "secondary"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
  }
}

resource "google_network_connectivity_spoke" "tertiary_spoke" {
  name        = "tertiary-spoke-${random_id.suffix.hex}"
  project     = var.project_id
  location    = var.tertiary_region
  hub         = google_network_connectivity_hub.enterprise_wan_hub.id
  description = "Tertiary region spoke for ${var.tertiary_region}"

  labels = {
    purpose     = "global-content-delivery"
    region      = "tertiary" 
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
  }
}

# Anywhere Cache instances for regional high-performance caching
resource "time_sleep" "cache_creation_delay" {
  depends_on      = [google_storage_bucket.global_content_bucket]
  create_duration = "60s"
}

resource "google_storage_anywhere_cache" "primary_cache" {
  bucket           = google_storage_bucket.global_content_bucket.name
  zone             = "${var.primary_region}-a"
  ttl              = "${var.cache_ttl_seconds}s"
  admission_policy = var.cache_admission_policy

  depends_on = [time_sleep.cache_creation_delay]
}

resource "google_storage_anywhere_cache" "secondary_cache" {
  bucket           = google_storage_bucket.global_content_bucket.name
  zone             = "${var.secondary_region}-b"
  ttl              = "${var.cache_ttl_seconds}s"
  admission_policy = var.cache_admission_policy

  depends_on = [time_sleep.cache_creation_delay]
}

resource "google_storage_anywhere_cache" "tertiary_cache" {
  bucket           = google_storage_bucket.global_content_bucket.name
  zone             = "${var.tertiary_region}-a"
  ttl              = "${var.cache_ttl_seconds}s"
  admission_policy = var.cache_admission_policy

  depends_on = [time_sleep.cache_creation_delay]
}

# VPC Network for compute instances and load balancing
resource "google_compute_network" "content_delivery_network" {
  name                    = "${var.network_name}-${random_id.suffix.hex}"
  project                 = var.project_id
  auto_create_subnetworks = var.auto_create_subnetworks
  description             = "VPC network for global content delivery infrastructure"
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Firewall rules for HTTP/HTTPS traffic
resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https-${random_id.suffix.hex}"
  project = var.project_id
  network = google_compute_network.content_delivery_network.name

  description = "Allow HTTP and HTTPS traffic for content servers"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = var.allowed_source_ranges
  target_tags   = ["content-server"]
}

# Firewall rule for SSH access
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-${random_id.suffix.hex}"
  project = var.project_id
  network = google_compute_network.content_delivery_network.name

  description = "Allow SSH access for instance management"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_source_ranges
  target_tags   = ["content-server"]
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_check" {
  name    = "allow-health-check-${random_id.suffix.hex}"
  project = var.project_id
  network = google_compute_network.content_delivery_network.name

  description = "Allow health check traffic from Google Cloud load balancer"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Google Cloud health check IP ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]
  
  target_tags = ["content-server"]
}

# Content server instances across regions
resource "google_compute_instance" "primary_content_server" {
  name         = "content-server-primary-${random_id.suffix.hex}"
  project      = var.project_id
  zone         = "${var.primary_region}-a"
  machine_type = var.compute_machine_type
  description  = "Primary region content server for global delivery"

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = var.compute_disk_size
      type  = var.compute_disk_type
    }
  }

  # Network configuration with external IP
  network_interface {
    network = google_compute_network.content_delivery_network.name
    access_config {
      # Ephemeral external IP
    }
  }

  tags = ["content-server"]

  # Startup script for nginx installation and configuration
  metadata_startup_script = templatefile("${path.module}/scripts/content-server-startup.sh.tpl", {
    region_name     = var.primary_region
    zone_name       = "${var.primary_region}-a"
    server_role     = "primary"
    bucket_name     = google_storage_bucket.global_content_bucket.name
    environment     = var.environment
  })

  # Consistent labeling
  labels = {
    purpose     = "content-server"
    region      = "primary"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
    owner       = var.owner
  }

  # Service account with necessary permissions
  service_account {
    email = google_service_account.content_server_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [
    google_compute_firewall.allow_http_https,
    google_compute_firewall.allow_ssh,
    google_service_account.content_server_sa
  ]
}

resource "google_compute_instance" "secondary_content_server" {
  name         = "content-server-secondary-${random_id.suffix.hex}"
  project      = var.project_id
  zone         = "${var.secondary_region}-b"
  machine_type = var.compute_machine_type
  description  = "Secondary region content server for global delivery"

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = var.compute_disk_size
      type  = var.compute_disk_type
    }
  }

  # Network configuration with external IP
  network_interface {
    network = google_compute_network.content_delivery_network.name
    access_config {
      # Ephemeral external IP
    }
  }

  tags = ["content-server"]

  # Startup script for nginx installation and configuration
  metadata_startup_script = templatefile("${path.module}/scripts/content-server-startup.sh.tpl", {
    region_name     = var.secondary_region
    zone_name       = "${var.secondary_region}-b"
    server_role     = "secondary"
    bucket_name     = google_storage_bucket.global_content_bucket.name
    environment     = var.environment
  })

  # Consistent labeling
  labels = {
    purpose     = "content-server"
    region      = "secondary"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
    owner       = var.owner
  }

  # Service account with necessary permissions
  service_account {
    email = google_service_account.content_server_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [
    google_compute_firewall.allow_http_https,
    google_compute_firewall.allow_ssh,
    google_service_account.content_server_sa
  ]
}

resource "google_compute_instance" "tertiary_content_server" {
  name         = "content-server-tertiary-${random_id.suffix.hex}"
  project      = var.project_id
  zone         = "${var.tertiary_region}-a"
  machine_type = var.compute_machine_type
  description  = "Tertiary region content server for global delivery"

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = var.compute_disk_size
      type  = var.compute_disk_type
    }
  }

  # Network configuration with external IP
  network_interface {
    network = google_compute_network.content_delivery_network.name
    access_config {
      # Ephemeral external IP
    }
  }

  tags = ["content-server"]

  # Startup script for nginx installation and configuration
  metadata_startup_script = templatefile("${path.module}/scripts/content-server-startup.sh.tpl", {
    region_name     = var.tertiary_region
    zone_name       = "${var.tertiary_region}-a"
    server_role     = "tertiary"
    bucket_name     = google_storage_bucket.global_content_bucket.name
    environment     = var.environment
  })

  # Consistent labeling
  labels = {
    purpose     = "content-server"
    region      = "tertiary"
    recipe      = "cloud-wan-anywhere-cache"
    environment = var.environment
    owner       = var.owner
  }

  # Service account with necessary permissions
  service_account {
    email = google_service_account.content_server_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [
    google_compute_firewall.allow_http_https,
    google_compute_firewall.allow_ssh,
    google_service_account.content_server_sa
  ]
}

# Service account for content server instances
resource "google_service_account" "content_server_sa" {
  account_id   = "content-server-sa-${random_id.suffix.hex}"
  project      = var.project_id
  display_name = "Content Server Service Account"
  description  = "Service account for content server instances with minimal required permissions"
}

# IAM bindings for service account
resource "google_project_iam_member" "content_server_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.content_server_sa.email}"
}

resource "google_project_iam_member" "content_server_monitoring_writer" {
  count   = var.enable_monitoring ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.content_server_sa.email}"
}

resource "google_project_iam_member" "content_server_logging_writer" {
  count   = var.enable_logging ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.content_server_sa.email}"
}

# Instance groups for load balancing
resource "google_compute_instance_group" "primary_instance_group" {
  name    = "primary-instance-group-${random_id.suffix.hex}"
  project = var.project_id
  zone    = "${var.primary_region}-a"
  
  description = "Instance group for primary region content servers"
  
  instances = [google_compute_instance.primary_content_server.self_link]
  
  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "secondary_instance_group" {
  name    = "secondary-instance-group-${random_id.suffix.hex}"
  project = var.project_id
  zone    = "${var.secondary_region}-b"
  
  description = "Instance group for secondary region content servers"
  
  instances = [google_compute_instance.secondary_content_server.self_link]
  
  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "tertiary_instance_group" {
  name    = "tertiary-instance-group-${random_id.suffix.hex}"
  project = var.project_id
  zone    = "${var.tertiary_region}-a"
  
  description = "Instance group for tertiary region content servers"
  
  instances = [google_compute_instance.tertiary_content_server.self_link]
  
  named_port {
    name = "http"
    port = 80
  }
}

# Global IP address for the load balancer
resource "google_compute_global_address" "content_delivery_ip" {
  name        = "content-delivery-ip-${random_id.suffix.hex}"
  project     = var.project_id
  description = "Global IP address for content delivery load balancer"
  
  depends_on = [google_project_service.required_apis]
}

# Health check for backend services
resource "google_compute_health_check" "content_health_check" {
  name    = "content-health-check-${random_id.suffix.hex}"
  project = var.project_id
  
  description = "Health check for content servers"
  
  timeout_sec         = var.health_check_timeout
  check_interval_sec  = var.health_check_interval
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# Backend bucket for Cloud Storage integration with CDN
resource "google_compute_backend_bucket" "content_backend_bucket" {
  name        = "content-backend-bucket-${random_id.suffix.hex}"
  project     = var.project_id
  description = "Backend bucket for global content delivery with Cloud CDN"
  
  bucket_name = google_storage_bucket.global_content_bucket.name
  enable_cdn  = var.enable_cdn
  
  # CDN policy configuration for optimal caching
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode                   = var.cdn_cache_mode
      default_ttl                  = var.cdn_default_ttl
      max_ttl                      = var.cdn_max_ttl
      client_ttl                   = var.cdn_client_ttl
      negative_caching             = true
      serve_while_stale            = 86400  # 24 hours
      request_coalescing           = true
      
      # Negative caching policy for error responses
      negative_caching_policy {
        code = 404
        ttl  = 300
      }
      
      negative_caching_policy {
        code = 410
        ttl  = 300
      }
      
      # Cache key policy for optimal cache hit rates
      cache_key_policy {
        include_http_headers   = ["Accept-Encoding"]
        query_string_whitelist = ["version", "lang"]
      }
    }
  }
  
  depends_on = [google_storage_bucket.global_content_bucket]
}

# Backend service for compute instances with CDN
resource "google_compute_backend_service" "content_backend_service" {
  name        = "content-backend-service-${random_id.suffix.hex}"
  project     = var.project_id
  description = "Backend service for content servers with CDN enabled"
  
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  enable_cdn  = var.enable_cdn
  
  # CDN policy configuration
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode           = var.cdn_cache_mode
      default_ttl          = var.cdn_default_ttl
      max_ttl              = var.cdn_max_ttl
      client_ttl           = var.cdn_client_ttl
      negative_caching     = true
      serve_while_stale    = 86400
      request_coalescing   = true
      
      negative_caching_policy {
        code = 404
        ttl  = 300
      }
    }
  }
  
  # Backend configuration for all regions
  backend {
    group           = google_compute_instance_group.primary_instance_group.self_link
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  backend {
    group           = google_compute_instance_group.secondary_instance_group.self_link
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  backend {
    group           = google_compute_instance_group.tertiary_instance_group.self_link
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  health_checks = [google_compute_health_check.content_health_check.self_link]
  
  # Access logging configuration
  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = 1.0
    }
  }
}

# URL map for routing between backend bucket and backend service
resource "google_compute_url_map" "content_url_map" {
  name        = "content-url-map-${random_id.suffix.hex}"
  project     = var.project_id
  description = "URL map for routing between static content and dynamic services"
  
  # Default service for dynamic content
  default_service = google_compute_backend_service.content_backend_service.self_link
  
  # Path matcher for static content served from bucket
  path_matcher {
    name            = "static-content"
    default_service = google_compute_backend_bucket.content_backend_bucket.self_link
    
    path_rule {
      paths   = ["/static/*", "/*.html", "/*.css", "/*.js", "/*.png", "/*.jpg", "/*.jpeg", "/*.gif", "/*.dat"]
      service = google_compute_backend_bucket.content_backend_bucket.self_link
    }
  }
  
  # Host rule to route static content requests
  host_rule {
    hosts        = ["*"]
    path_matcher = "static-content"
  }
}

# Target HTTP proxy
resource "google_compute_target_http_proxy" "content_target_proxy" {
  name    = "content-target-proxy-${random_id.suffix.hex}"
  project = var.project_id
  
  description = "Target HTTP proxy for global content delivery"
  url_map     = google_compute_url_map.content_url_map.self_link
}

# Global forwarding rule to complete the load balancer setup
resource "google_compute_global_forwarding_rule" "content_forwarding_rule" {
  name       = "content-forwarding-rule-${random_id.suffix.hex}"
  project    = var.project_id
  
  description   = "Global forwarding rule for content delivery load balancer"
  ip_address    = google_compute_global_address.content_delivery_ip.address
  ip_protocol   = "TCP"
  port_range    = "80"
  target        = google_compute_target_http_proxy.content_target_proxy.self_link
  
  depends_on = [google_compute_global_address.content_delivery_ip]
}

# Cloud Monitoring Dashboard (optional)
resource "google_monitoring_dashboard" "content_delivery_dashboard" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "Global Content Delivery Performance - ${random_id.suffix.hex}"
  
  dashboard_json = jsonencode({
    displayName = "Global Content Delivery Performance - ${random_id.suffix.hex}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "CDN Cache Hit Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"http_load_balancer\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_RATE"
                        crossSeriesReducer  = "REDUCE_SUM"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Backend Response Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"http_load_balancer\" AND metric.type=\"loadbalancing.googleapis.com/https/backend_latencies\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_MEAN"
                        crossSeriesReducer  = "REDUCE_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Storage Bucket Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/api/request_count\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_RATE"
                        crossSeriesReducer  = "REDUCE_SUM"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}