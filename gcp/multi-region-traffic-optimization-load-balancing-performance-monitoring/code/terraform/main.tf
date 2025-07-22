# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  
  # Regional configurations
  regions = {
    us = {
      region = var.primary_region
      zone   = var.primary_zone
      subnet_cidr = var.vpc_cidr_ranges.us_subnet
    }
    eu = {
      region = var.secondary_region
      zone   = var.secondary_zone
      subnet_cidr = var.vpc_cidr_ranges.eu_subnet
    }
    apac = {
      region = var.tertiary_region
      zone   = var.tertiary_zone
      subnet_cidr = var.vpc_cidr_ranges.apac_subnet
    }
  }
  
  # Common labels
  common_labels = merge(var.labels, {
    resource-suffix = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "networkmanagement.googleapis.com"
  ]) : []

  service = each.value
  project = var.project_id

  disable_dependent_services = true
}

# Create global VPC network
resource "google_compute_network" "global_vpc" {
  name                    = "${var.resource_prefix}-global-vpc-${local.resource_suffix}"
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "Global VPC network for multi-region traffic optimization"

  depends_on = [google_project_service.required_apis]
}

# Create regional subnets
resource "google_compute_subnetwork" "regional_subnets" {
  for_each = local.regions

  name          = "${var.resource_prefix}-${each.key}-subnet-${local.resource_suffix}"
  network       = google_compute_network.global_vpc.id
  ip_cidr_range = each.value.subnet_cidr
  region        = each.value.region
  description   = "Subnet for ${each.key} region"

  # Enable private Google access for instances without external IPs
  private_ip_google_access = true

  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for HTTP/HTTPS traffic
resource "google_compute_firewall" "allow_http_https" {
  name        = "${var.resource_prefix}-allow-http-https-${local.resource_suffix}"
  network     = google_compute_network.global_vpc.id
  description = "Allow HTTP and HTTPS traffic from anywhere"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = var.allowed_source_ranges
  target_tags   = ["http-server"]

  depends_on = [google_compute_network.global_vpc]
}

# Create firewall rule for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.resource_prefix}-allow-health-checks-${local.resource_suffix}"
  network     = google_compute_network.global_vpc.id
  description = "Allow Google Cloud health check ranges"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # Google Cloud health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["http-server"]

  depends_on = [google_compute_network.global_vpc]
}

# Create startup script for application instances
resource "google_compute_instance_template" "app_template" {
  name        = "${var.resource_prefix}-app-template-${local.resource_suffix}"
  description = "Instance template for multi-region application servers"

  machine_type = var.instance_machine_type

  # Boot disk configuration
  disk {
    source_image = "${var.instance_image_project}/${var.instance_image_family}"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-standard"
  }

  # Network interface configuration
  network_interface {
    subnetwork = google_compute_subnetwork.regional_subnets["us"].id
    # No external IP - instances will use Cloud NAT or private connectivity
  }

  # Instance metadata and startup script
  metadata = {
    startup-script = templatefile("${path.module}/startup-script.sh", {
      region_name = "TEMPLATE"
    })
  }

  # Service account with minimal permissions
  service_account {
    email  = google_service_account.app_service_account.email
    scopes = ["cloud-platform"]
  }

  # Security and access configuration
  tags = ["http-server"]

  labels = local.common_labels

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_compute_subnetwork.regional_subnets,
    google_service_account.app_service_account
  ]
}

# Create service account for application instances
resource "google_service_account" "app_service_account" {
  account_id   = "${var.resource_prefix}-app-sa-${local.resource_suffix}"
  display_name = "Application Service Account"
  description  = "Service account for application instances"
}

# Grant minimal IAM permissions to service account
resource "google_project_iam_member" "app_service_account_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_service_account.email}"
}

# Create managed instance groups in each region
resource "google_compute_instance_group_manager" "regional_groups" {
  for_each = local.regions

  name        = "${var.resource_prefix}-${each.key}-ig-${local.resource_suffix}"
  description = "Managed instance group for ${each.key} region"

  base_instance_name = "${var.resource_prefix}-${each.key}-instance"
  zone               = each.value.zone

  version {
    instance_template = google_compute_instance_template.app_template.id
  }

  target_size = var.instance_group_size

  # Named ports for load balancer
  named_port {
    name = "http"
    port = 8080
  }

  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_health_check.app_health_check.id
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

  depends_on = [
    google_compute_instance_template.app_template,
    google_compute_health_check.app_health_check
  ]
}

# Create HTTP health check for load balancer
resource "google_compute_health_check" "app_health_check" {
  name        = "${var.resource_prefix}-global-health-check-${local.resource_suffix}"
  description = "Global health check for multi-region application"

  timeout_sec         = var.health_check_settings.timeout_sec
  check_interval_sec  = var.health_check_settings.check_interval_sec
  healthy_threshold   = var.health_check_settings.healthy_threshold
  unhealthy_threshold = var.health_check_settings.unhealthy_threshold

  http_health_check {
    port         = var.health_check_settings.port
    request_path = var.health_check_settings.request_path
  }

  log_config {
    enable = true
  }
}

# Create global backend service with CDN enabled
resource "google_compute_backend_service" "global_backend" {
  name        = "${var.resource_prefix}-global-backend-${local.resource_suffix}"
  description = "Global backend service with CDN and advanced load balancing"

  protocol                        = "HTTP"
  load_balancing_scheme          = "EXTERNAL"
  locality_lb_policy             = var.backend_service_settings.locality_lb_policy
  health_checks                  = [google_compute_health_check.app_health_check.id]
  enable_cdn                     = true
  session_affinity               = "NONE"
  timeout_sec                    = 30
  connection_draining_timeout_sec = 60

  # Add regional backend instances
  dynamic "backend" {
    for_each = google_compute_instance_group_manager.regional_groups
    content {
      group           = backend.value.instance_group
      balancing_mode  = var.backend_service_settings.balancing_mode
      capacity_scaler = var.backend_service_settings.capacity_scaler
      max_utilization = var.backend_service_settings.max_utilization
    }
  }

  # CDN configuration
  cdn_policy {
    cache_mode       = var.cdn_settings.cache_mode
    default_ttl      = var.cdn_settings.default_ttl
    max_ttl          = var.cdn_settings.max_ttl
    client_ttl       = var.cdn_settings.client_ttl
    negative_caching = var.cdn_settings.negative_caching

    # Cache key policy for optimization
    cache_key_policy {
      include_protocol    = true
      include_host        = true
      include_query_string = true
    }

    # Negative caching policy for error responses
    dynamic "negative_caching_policy" {
      for_each = var.cdn_settings.negative_caching ? [1] : []
      content {
        code = 404
        ttl  = 300
      }
    }

    dynamic "negative_caching_policy" {
      for_each = var.cdn_settings.negative_caching ? [1] : []
      content {
        code = 500
        ttl  = 60
      }
    }
  }

  # Circuit breaker configuration for resilience
  circuit_breakers {
    max_requests         = var.circuit_breaker_settings.max_requests
    max_pending_requests = var.circuit_breaker_settings.max_pending_requests
    max_retries          = var.circuit_breaker_settings.max_retries
    max_connections      = var.circuit_breaker_settings.max_connections
  }

  # Outlier detection for automatic backend removal
  outlier_detection {
    consecutive_errors                    = var.outlier_detection_settings.consecutive_errors
    consecutive_gateway_failure           = var.outlier_detection_settings.consecutive_gateway_failure
    interval {
      seconds = var.outlier_detection_settings.interval_sec
    }
    base_ejection_time {
      seconds = var.outlier_detection_settings.base_ejection_time_sec
    }
    max_ejection_percent = var.outlier_detection_settings.max_ejection_percent
  }

  # Compression for performance optimization
  compression_mode = var.cdn_settings.compression ? "AUTOMATIC" : "DISABLED"

  # Custom request headers for backend identification
  custom_request_headers = [
    "X-Load-Balancer:Google-Global-LB",
    "X-Backend-Region:{client_region}"
  ]

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  depends_on = [
    google_compute_instance_group_manager.regional_groups,
    google_compute_health_check.app_health_check
  ]
}

# Create URL map for load balancer routing
resource "google_compute_url_map" "global_url_map" {
  name            = "${var.resource_prefix}-global-url-map-${local.resource_suffix}"
  description     = "Global URL map for multi-region traffic routing"
  default_service = google_compute_backend_service.global_backend.id

  # Default host rule (can be extended for multiple services)
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  # Path matcher for routing rules
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.global_backend.id
  }

  depends_on = [google_compute_backend_service.global_backend]
}

# Create target HTTP proxy
resource "google_compute_target_http_proxy" "global_http_proxy" {
  name    = "${var.resource_prefix}-global-http-proxy-${local.resource_suffix}"
  url_map = google_compute_url_map.global_url_map.id

  depends_on = [google_compute_url_map.global_url_map]
}

# Create target HTTPS proxy (if SSL certificates are provided)
resource "google_compute_target_https_proxy" "global_https_proxy" {
  count = length(var.ssl_certificates) > 0 ? 1 : 0

  name             = "${var.resource_prefix}-global-https-proxy-${local.resource_suffix}"
  url_map          = google_compute_url_map.global_url_map.id
  ssl_certificates = var.ssl_certificates

  depends_on = [google_compute_url_map.global_url_map]
}

# Create global forwarding rule for HTTP traffic
resource "google_compute_global_forwarding_rule" "global_http_rule" {
  name       = "${var.resource_prefix}-global-http-rule-${local.resource_suffix}"
  target     = google_compute_target_http_proxy.global_http_proxy.id
  port_range = "80"

  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [google_compute_target_http_proxy.global_http_proxy]
}

# Create global forwarding rule for HTTPS traffic (if SSL certificates are provided)
resource "google_compute_global_forwarding_rule" "global_https_rule" {
  count = length(var.ssl_certificates) > 0 ? 1 : 0

  name       = "${var.resource_prefix}-global-https-rule-${local.resource_suffix}"
  target     = google_compute_target_https_proxy.global_https_proxy[0].id
  port_range = "443"

  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [google_compute_target_https_proxy.global_https_proxy]
}

# Network Intelligence Center connectivity tests
resource "google_network_management_connectivity_test" "inter_region_tests" {
  for_each = var.enable_network_intelligence ? {
    us-to-eu   = { source = "us", destination = "eu" }
    us-to-apac = { source = "us", destination = "apac" }
    eu-to-apac = { source = "eu", destination = "apac" }
  } : {}

  name = "${var.resource_prefix}-${each.value.source}-to-${each.value.destination}-test-${local.resource_suffix}"

  source {
    instance = google_compute_instance_group_manager.regional_groups[each.value.source].instance_group
  }

  destination {
    instance = google_compute_instance_group_manager.regional_groups[each.value.destination].instance_group
    port     = 8080
  }

  protocol = "TCP"

  depends_on = [
    google_compute_instance_group_manager.regional_groups,
    google_project_service.required_apis
  ]
}

# Cloud Monitoring uptime check
resource "google_monitoring_uptime_check_config" "global_app_uptime" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${var.resource_prefix}-global-app-uptime-${local.resource_suffix}"
  timeout      = var.monitoring_settings.uptime_check_timeout
  period       = var.monitoring_settings.uptime_check_period

  http_check {
    path         = "/"
    port         = 80
    use_ssl      = false
    validate_ssl = false
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = google_compute_global_forwarding_rule.global_http_rule.ip_address
    }
  }

  content_matchers {
    content = "Load balancer working correctly!"
    matcher = "CONTAINS_STRING"
  }

  depends_on = [
    google_compute_global_forwarding_rule.global_http_rule,
    google_project_service.required_apis
  ]
}

# Create alerting policy for high latency
resource "google_monitoring_alert_policy" "high_latency_alert" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${var.resource_prefix}-high-latency-alert-${local.resource_suffix}"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Load balancer latency > ${var.monitoring_settings.alert_latency_threshold}s"

    condition_threshold {
      filter          = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/request_duration\""
      duration        = var.monitoring_settings.alert_duration
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.monitoring_settings.alert_latency_threshold

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.backend_service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }

  depends_on = [
    google_compute_backend_service.global_backend,
    google_project_service.required_apis
  ]
}

# Create startup script file
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    region_name = var.primary_region
  })
}

# Create Cloud NAT for outbound internet access (optional)
resource "google_compute_router" "regional_routers" {
  for_each = local.regions

  name    = "${var.resource_prefix}-${each.key}-router-${local.resource_suffix}"
  region  = each.value.region
  network = google_compute_network.global_vpc.id

  depends_on = [google_compute_network.global_vpc]
}

resource "google_compute_router_nat" "regional_nat" {
  for_each = local.regions

  name                               = "${var.resource_prefix}-${each.key}-nat-${local.resource_suffix}"
  router                             = google_compute_router.regional_routers[each.key].name
  region                             = each.value.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [google_compute_router.regional_routers]
}