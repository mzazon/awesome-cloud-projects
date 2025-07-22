# Main Terraform Configuration for Distributed Edge Computing Networks
# This file creates a global edge computing infrastructure using Cloud CDN and Compute Engine

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming conventions
  resource_suffix = random_id.suffix.hex
  network_name    = "${var.network_name}-${local.resource_suffix}"
  
  # Create regional subnet ranges
  regional_subnets = {
    for i, region in var.regions : region => "10.${i + 1}.0.0/16"
  }
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    created-by    = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create global VPC network for edge infrastructure
resource "google_compute_network" "edge_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
  description            = "Global VPC network for distributed edge computing infrastructure"
  
  depends_on = [google_project_service.required_apis]
}

# Create regional subnets for each edge computing cluster
resource "google_compute_subnetwork" "regional_subnets" {
  for_each = local.regional_subnets
  
  name                     = "${local.network_name}-${each.key}"
  ip_cidr_range           = each.value
  region                  = each.key
  network                 = google_compute_network.edge_network.id
  private_ip_google_access = true
  description             = "Subnet for edge computing cluster in ${each.key}"
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling       = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule to allow HTTP/HTTPS traffic for edge services
resource "google_compute_firewall" "allow_web_traffic" {
  name    = "${local.network_name}-allow-web"
  network = google_compute_network.edge_network.name
  
  description = "Allow HTTP/HTTPS traffic to edge servers"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["edge-server"]
  priority      = 1000
}

# Firewall rule to allow health check traffic from Google Cloud Load Balancing
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${local.network_name}-allow-health-check"
  network = google_compute_network.edge_network.name
  
  description = "Allow health check traffic from Google Cloud Load Balancing"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["edge-server"]
  priority      = 1000
}

# Firewall rule to allow internal communication between edge nodes
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.network_name}-allow-internal"
  network = google_compute_network.edge_network.name
  
  description = "Allow internal communication between edge nodes"
  
  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["1-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = ["10.0.0.0/8"]
  target_tags   = ["edge-server"]
  priority      = 1000
}

# Cloud Storage buckets for content origins (optional)
resource "google_storage_bucket" "content_origins" {
  for_each = var.enable_storage_origins ? toset(var.regions) : []
  
  name          = "edge-origin-${each.key}-${local.resource_suffix}"
  location      = each.key
  storage_class = var.storage_class
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = false
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

# Make storage buckets publicly readable for CDN access
resource "google_storage_bucket_iam_member" "public_read" {
  for_each = var.enable_storage_origins ? toset(var.regions) : []
  
  bucket = google_storage_bucket.content_origins[each.key].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload sample content to storage buckets
resource "google_storage_bucket_object" "sample_content" {
  for_each = var.enable_storage_origins ? toset(var.regions) : []
  
  name    = "index.html"
  bucket  = google_storage_bucket.content_origins[each.key].name
  content = "<h1>Static Content from ${each.key}</h1><p>Served via Cloud CDN</p>"
  
  content_type = "text/html"
}

# Instance template for edge computing nodes
resource "google_compute_instance_template" "edge_template" {
  for_each = toset(var.regions)
  
  name_prefix  = "edge-template-${each.key}-"
  machine_type = var.machine_type
  region       = each.key
  
  description = "Instance template for edge computing nodes in ${each.key}"
  
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2404-lts"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-standard"
    disk_size_gb = 20
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.regional_subnets[each.key].id
    # No external IP - instances will use NAT for outbound connectivity
  }
  
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  tags = ["edge-server"]
  
  labels = merge(local.common_labels, {
    region = each.key
    role   = "edge-server"
  })
  
  metadata = {
    startup-script = templatefile("${path.module}/startup-script.sh", {
      region = each.key
    })
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Startup script for edge computing instances
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content  = <<-EOF
    #!/bin/bash
    
    # Update system packages
    apt-get update
    apt-get install -y nginx curl jq
    
    # Get instance metadata
    INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
    ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d/ -f4)
    REGION=$${ZONE%-*}
    
    # Configure nginx for edge processing
    cat > /var/www/html/index.html << HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>Edge Node - $${INSTANCE_NAME}</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .header { background: #4285f4; color: white; padding: 20px; border-radius: 5px; }
            .content { margin: 20px 0; }
            .metadata { background: #f5f5f5; padding: 15px; border-radius: 5px; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>🌐 Edge Computing Node</h1>
        </div>
        <div class="content">
            <div class="metadata">
                <h3>Instance Information</h3>
                <p><strong>Server:</strong> $${INSTANCE_NAME}</p>
                <p><strong>Zone:</strong> $${ZONE}</p>
                <p><strong>Region:</strong> $${REGION}</p>
                <p><strong>Timestamp:</strong> $(date)</p>
                <p><strong>Status:</strong> Processing dynamic content at the edge</p>
            </div>
            <div class="metadata" style="margin-top: 20px;">
                <h3>Edge Computing Features</h3>
                <ul>
                    <li>Low-latency content delivery</li>
                    <li>Dynamic content processing</li>
                    <li>Regional failover support</li>
                    <li>Auto-scaling capabilities</li>
                </ul>
            </div>
        </div>
    </body>
    </html>
HTML
    
    # Configure nginx
    cat > /etc/nginx/sites-available/default << NGINX
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        
        root /var/www/html;
        index index.html index.htm;
        
        server_name _;
        
        location / {
            try_files \$uri \$uri/ =404;
            add_header X-Edge-Region "$${REGION}";
            add_header X-Edge-Instance "$${INSTANCE_NAME}";
        }
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
NGINX
    
    # Start and enable nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Configure log rotation
    cat > /etc/logrotate.d/nginx << LOGROTATE
    /var/log/nginx/*.log {
        daily
        missingok
        rotate 52
        compress
        delaycompress
        notifempty
        create 644 nginx nginx
        postrotate
            systemctl reload nginx
        endscript
    }
LOGROTATE
    
    echo "Edge computing node setup completed"
  EOF
}

# Managed instance groups for regional edge clusters
resource "google_compute_region_instance_group_manager" "edge_clusters" {
  for_each = toset(var.regions)
  
  name   = "edge-group-${each.key}"
  region = each.key
  
  description = "Managed instance group for edge computing cluster in ${each.key}"
  
  base_instance_name = "edge-${each.key}"
  
  version {
    instance_template = google_compute_instance_template.edge_template[each.key].id
  }
  
  target_size = var.min_replicas
  
  named_port {
    name = "http"
    port = 80
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.edge_health_check.id
    initial_delay_sec = 300
  }
  
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
  }
}

# Regional autoscalers for dynamic capacity management
resource "google_compute_region_autoscaler" "edge_autoscalers" {
  for_each = toset(var.regions)
  
  name   = "edge-autoscaler-${each.key}"
  region = each.key
  target = google_compute_region_instance_group_manager.edge_clusters[each.key].id
  
  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = 60
    
    cpu_utilization {
      target = var.target_cpu_utilization
    }
    
    load_balancing_utilization {
      target = 0.8
    }
  }
}

# Health check for backend services
resource "google_compute_health_check" "edge_health_check" {
  name = "edge-health-check-${local.resource_suffix}"
  
  description = "Health check for edge computing backend services"
  
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port               = var.health_check_port
    request_path       = var.health_check_path
    proxy_header       = "NONE"
    response           = ""
  }
  
  log_config {
    enable = var.enable_logging
  }
}

# Backend service with CDN enabled
resource "google_compute_backend_service" "edge_backend_service" {
  name = "edge-backend-${local.resource_suffix}"
  
  description             = "Backend service for distributed edge computing network"
  protocol                = "HTTP"
  port_name              = "http"
  load_balancing_scheme  = "EXTERNAL_MANAGED"
  timeout_sec            = 30
  enable_cdn             = true
  
  health_checks = [google_compute_health_check.edge_health_check.id]
  
  # CDN configuration
  cdn_policy {
    cache_mode        = var.cdn_cache_mode
    default_ttl       = var.cdn_default_ttl
    max_ttl          = var.cdn_max_ttl
    client_ttl       = var.cdn_client_ttl
    negative_caching = true
    
    negative_caching_policy {
      code = 404
      ttl  = 60
    }
    
    negative_caching_policy {
      code = 500
      ttl  = 10
    }
    
    serve_while_stale = 86400
  }
  
  # Add regional instance groups as backends
  dynamic "backend" {
    for_each = var.regions
    
    content {
      group           = google_compute_region_instance_group_manager.edge_clusters[backend.value].instance_group
      balancing_mode  = "UTILIZATION"
      max_utilization = 0.8
      capacity_scaler = 1.0
    }
  }
  
  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    
    content {
      enable      = true
      sample_rate = var.log_config_sample_rate
    }
  }
  
  locality_lb_policy = "ROUND_ROBIN"
  
  outlier_detection {
    consecutive_errors                    = 5
    consecutive_gateway_failure_threshold = 3
    interval {
      seconds = 30
    }
    base_ejection_time {
      seconds = 30
    }
    max_ejection_percent = 50
  }
}

# URL map for request routing
resource "google_compute_url_map" "edge_url_map" {
  name = "edge-url-map-${local.resource_suffix}"
  
  description = "URL map for distributed edge computing network"
  
  default_service = google_compute_backend_service.edge_backend_service.id
  
  # Add path-based routing rules if needed
  path_matcher {
    name            = "edge-paths"
    default_service = google_compute_backend_service.edge_backend_service.id
    
    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.edge_backend_service.id
    }
    
    path_rule {
      paths   = ["/static/*"]
      service = google_compute_backend_service.edge_backend_service.id
    }
  }
  
  host_rule {
    hosts        = [var.domain_name, "*.${var.domain_name}"]
    path_matcher = "edge-paths"
  }
}

# Target HTTP proxy
resource "google_compute_target_http_proxy" "edge_http_proxy" {
  name    = "edge-http-proxy-${local.resource_suffix}"
  url_map = google_compute_url_map.edge_url_map.id
  
  description = "HTTP proxy for distributed edge computing network"
}

# Reserve global static IP address
resource "google_compute_global_address" "edge_global_ip" {
  name         = "edge-global-ip-${local.resource_suffix}"
  address_type = "EXTERNAL"
  
  description = "Global static IP address for edge computing network"
}

# Global forwarding rule
resource "google_compute_global_forwarding_rule" "edge_forwarding_rule" {
  name       = "edge-forwarding-rule-${local.resource_suffix}"
  target     = google_compute_target_http_proxy.edge_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.edge_global_ip.address
  
  description = "Global forwarding rule for edge computing network"
  
  labels = local.common_labels
}

# Cloud DNS managed zone (optional)
resource "google_dns_managed_zone" "edge_zone" {
  count = var.enable_dns ? 1 : 0
  
  name     = "edge-zone-${local.resource_suffix}"
  dns_name = "${var.domain_name}."
  
  description = "DNS zone for edge computing network"
  
  visibility = "public"
  
  labels = local.common_labels
}

# DNS A record pointing to global load balancer
resource "google_dns_record_set" "edge_a_record" {
  count = var.enable_dns ? 1 : 0
  
  name         = "${var.domain_name}."
  managed_zone = google_dns_managed_zone.edge_zone[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.edge_global_ip.address]
}

# DNS CNAME record for www subdomain
resource "google_dns_record_set" "edge_cname_record" {
  count = var.enable_dns ? 1 : 0
  
  name         = "www.${var.domain_name}."
  managed_zone = google_dns_managed_zone.edge_zone[0].name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["${var.domain_name}."]
}