# Gaming Backend Performance Infrastructure with Cloud Memorystore and CDN
# This Terraform configuration deploys a high-performance gaming backend
# with Redis caching, global load balancing, and CDN for static assets

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  labels = merge(var.labels, {
    environment = var.environment
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create VPC network for gaming infrastructure
resource "google_compute_network" "gaming_network" {
  name                    = "gaming-network-${local.resource_suffix}"
  auto_create_subnetworks = false
  description            = "VPC network for gaming backend infrastructure"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for game servers and Redis
resource "google_compute_subnetwork" "gaming_subnet" {
  name          = "gaming-subnet-${local.resource_suffix}"
  network       = google_compute_network.gaming_network.id
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  description   = "Subnet for game servers and Redis instance"
  
  # Enable private Google access for managed services
  private_ip_google_access = true
}

# Create private service access for Redis
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "gaming-private-ip-${local.resource_suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.gaming_network.id
  description   = "Private IP range for Redis and managed services"
}

# Create private connection for managed services
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.gaming_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  deletion_policy         = "ABANDON"
}

# Create Cloud Memorystore Redis instance for gaming data
resource "google_redis_instance" "gaming_redis" {
  name           = "gaming-redis-${local.resource_suffix}"
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  
  # Network configuration
  authorized_network   = google_compute_network.gaming_network.id
  connect_mode        = "PRIVATE_SERVICE_ACCESS"
  redis_version       = var.redis_version
  
  # Security and performance configuration
  auth_enabled                = true
  transit_encryption_mode     = "SERVER_CLIENT"
  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "TWELVE_HOURS"
  }
  
  # Redis configuration for gaming workloads
  redis_configs = {
    maxmemory-policy = "allkeys-lru"
    notify-keyspace-events = "Ex"
    timeout = "300"
  }
  
  # Maintenance window
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
  
  display_name = "Gaming Redis Cluster"
  labels       = local.labels
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
}

# Create Cloud Storage bucket for game assets
resource "google_storage_bucket" "game_assets" {
  name          = "gaming-assets-${local.resource_suffix}"
  location      = var.region
  storage_class = var.storage_class
  
  # Enable public access for CDN
  uniform_bucket_level_access = true
  
  # Lifecycle management for asset optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for asset management
  versioning {
    enabled = true
  }
  
  # CORS configuration for web clients
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.labels
  
  depends_on = [google_project_service.required_apis]
}

# Make bucket publicly readable for CDN
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.game_assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload sample game assets with appropriate metadata
resource "google_storage_bucket_object" "game_config" {
  name   = "configs/game-config.json"
  bucket = google_storage_bucket.game_assets.name
  content = jsonencode({
    gameVersion = "1.2.3"
    maxPlayers  = 100
    serverRegion = var.region
  })
  content_type = "application/json"
  
  # Cache for 24 hours
  cache_control = "public, max-age=86400"
  
  metadata = {
    description = "Game configuration file"
    version     = "1.2.3"
  }
}

resource "google_storage_bucket_object" "sample_texture" {
  name    = "assets/textures/sample-texture.bin"
  bucket  = google_storage_bucket.game_assets.name
  content = "Sample game texture data for CDN testing"
  
  # Cache for 7 days
  cache_control = "public, max-age=604800"
  
  metadata = {
    description = "Sample texture asset"
    asset_type  = "texture"
  }
}

# Create firewall rules for game traffic
resource "google_compute_firewall" "allow_game_traffic" {
  name    = "allow-game-traffic-${local.resource_suffix}"
  network = google_compute_network.gaming_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["game-server"]
  description   = "Allow HTTP/HTTPS and game protocol traffic to game servers"
}

# Create firewall rule for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks-${local.resource_suffix}"
  network = google_compute_network.gaming_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  
  # Google Cloud health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["game-server"]
  description   = "Allow health check traffic from Google Cloud load balancers"
}

# Create instance template for game servers
resource "google_compute_instance_template" "game_server_template" {
  name_prefix  = "game-server-template-"
  machine_type = var.game_server_machine_type
  region       = var.region
  
  # Boot disk configuration
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.game_server_disk_size_gb
    disk_type    = "pd-standard"
  }
  
  # Network configuration
  network_interface {
    network    = google_compute_network.gaming_network.id
    subnetwork = google_compute_subnetwork.gaming_subnet.id
    
    # Assign external IP for internet access
    access_config {
      network_tier = var.network_tier
    }
  }
  
  # Service account with minimal permissions
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }
  
  # Startup script to configure game server
  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    redis_host     = google_redis_instance.gaming_redis.host
    redis_port     = google_redis_instance.gaming_redis.port
    bucket_name    = google_storage_bucket.game_assets.name
    project_id     = var.project_id
  })
  
  tags = ["game-server", "http-server"]
  labels = local.labels
  
  # Instance template lifecycle
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_redis_instance.gaming_redis]
}

# Create health check for game servers
resource "google_compute_health_check" "game_server_health" {
  name                = "game-server-health-${local.resource_suffix}"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3
  description         = "Health check for game server instances"
  
  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# Create managed instance group for auto-scaling
resource "google_compute_instance_group_manager" "game_server_group" {
  name               = "game-server-group-${local.resource_suffix}"
  base_instance_name = "game-server"
  zone               = var.zone
  target_size        = var.min_replicas
  
  version {
    instance_template = google_compute_instance_template.game_server_template.id
  }
  
  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_health_check.game_server_health.id
    initial_delay_sec = 300
  }
  
  # Update policy for rolling updates
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 1
    max_unavailable_fixed        = 0
  }
  
  depends_on = [google_compute_instance_template.game_server_template]
}

# Create autoscaler for dynamic scaling
resource "google_compute_autoscaler" "game_server_autoscaler" {
  name   = "game-server-autoscaler-${local.resource_suffix}"
  zone   = var.zone
  target = google_compute_instance_group_manager.game_server_group.id
  
  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = 300
    
    # Scale based on CPU utilization
    cpu_utilization {
      target = 0.75
    }
    
    # Scale based on load balancer utilization
    load_balancing_utilization {
      target = 0.8
    }
  }
}

# Create backend service for game servers
resource "google_compute_backend_service" "game_backend" {
  name                  = "game-backend-${local.resource_suffix}"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.game_server_health.id]
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  
  # CDN configuration for dynamic content caching
  enable_cdn = var.enable_cdn
  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 3600
    max_ttl                      = 86400
    client_ttl                   = 3600
    serve_while_stale            = 86400
    negative_caching             = true
    negative_caching_policy {
      code = 404
      ttl  = 120
    }
  }
  
  # Add instance group as backend
  backend {
    group           = google_compute_instance_group_manager.game_server_group.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  # Session affinity for gaming sessions
  session_affinity = "CLIENT_IP"
  
  # Connection draining timeout
  connection_draining_timeout_sec = 30
  
  description = "Backend service for game servers with CDN"
}

# Create backend bucket for static assets
resource "google_compute_backend_bucket" "game_assets_backend" {
  name        = "game-assets-backend-${local.resource_suffix}"
  bucket_name = google_storage_bucket.game_assets.name
  enable_cdn  = var.enable_cdn
  
  cdn_policy {
    default_ttl                  = 86400  # 24 hours
    max_ttl                      = 604800 # 7 days
    client_ttl                   = 86400  # 24 hours
    serve_while_stale            = 86400
    negative_caching             = true
    negative_caching_policy {
      code = 404
      ttl  = 300  # 5 minutes
    }
    
    # Cache static assets aggressively
    cache_key_policy {
      include_query_string = false
      include_protocol     = false
      include_host         = false
    }
  }
  
  description = "Backend bucket for game assets with CDN"
}

# Create URL map for routing
resource "google_compute_url_map" "game_url_map" {
  name            = "game-url-map-${local.resource_suffix}"
  default_service = google_compute_backend_service.game_backend.id
  description     = "URL map for routing game traffic and assets"
  
  # Route static assets to CDN-enabled bucket
  path_matcher {
    name            = "assets-matcher"
    default_service = google_compute_backend_bucket.game_assets_backend.id
    
    path_rule {
      paths   = ["/assets/*", "/configs/*"]
      service = google_compute_backend_bucket.game_assets_backend.id
    }
  }
  
  host_rule {
    hosts        = ["*"]
    path_matcher = "assets-matcher"
  }
}

# Create managed SSL certificate (optional)
resource "google_compute_managed_ssl_certificate" "game_ssl_cert" {
  count = length(var.ssl_domains) > 0 ? 1 : 0
  
  name = "game-ssl-cert-${local.resource_suffix}"
  
  managed {
    domains = var.ssl_domains
  }
  
  description = "Managed SSL certificate for gaming backend"
}

# Create target HTTPS proxy
resource "google_compute_target_https_proxy" "game_https_proxy" {
  count           = length(var.ssl_domains) > 0 ? 1 : 0
  name            = "game-https-proxy-${local.resource_suffix}"
  url_map         = google_compute_url_map.game_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.game_ssl_cert[0].id]
  description     = "HTTPS target proxy for gaming backend"
}

# Create target HTTP proxy for HTTP traffic
resource "google_compute_target_http_proxy" "game_http_proxy" {
  name        = "game-http-proxy-${local.resource_suffix}"
  url_map     = google_compute_url_map.game_url_map.id
  description = "HTTP target proxy for gaming backend"
}

# Reserve global static IP address
resource "google_compute_global_address" "game_frontend_ip" {
  name         = "game-frontend-ip-${local.resource_suffix}"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
  description  = "Global static IP for gaming backend frontend"
}

# Create global forwarding rule for HTTPS (if SSL domains provided)
resource "google_compute_global_forwarding_rule" "game_https_rule" {
  count       = length(var.ssl_domains) > 0 ? 1 : 0
  name        = "game-https-rule-${local.resource_suffix}"
  target      = google_compute_target_https_proxy.game_https_proxy[0].id
  ip_address  = google_compute_global_address.game_frontend_ip.address
  port_range  = "443"
  description = "Global forwarding rule for HTTPS traffic"
}

# Create global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "game_http_rule" {
  name        = "game-http-rule-${local.resource_suffix}"
  target      = google_compute_target_http_proxy.game_http_proxy.id
  ip_address  = google_compute_global_address.game_frontend_ip.address
  port_range  = "80"
  description = "Global forwarding rule for HTTP traffic"
}

# Output startup script content for reference
resource "local_file" "startup_script" {
  content = templatefile("${path.module}/startup-script.sh.tpl", {
    redis_host  = google_redis_instance.gaming_redis.host
    redis_port  = google_redis_instance.gaming_redis.port
    bucket_name = google_storage_bucket.game_assets.name
    project_id  = var.project_id
  })
  filename = "${path.module}/startup-script.sh"
}