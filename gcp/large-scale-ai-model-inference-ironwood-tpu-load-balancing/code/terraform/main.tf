# Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing
# This Terraform configuration deploys a comprehensive AI inference infrastructure
# using Google's Ironwood TPU v7, Vertex AI, and Cloud Load Balancing

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming convention with random suffix
  name_prefix = "${var.model_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    model       = var.model_name
    environment = var.environment
    terraform   = "true"
  })
  
  # Service account email
  tpu_service_account_email = google_service_account.tpu_inference.email
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "aiplatform.googleapis.com",
    "container.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "redis.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for TPU operations with least privilege principles
resource "google_service_account" "tpu_inference" {
  account_id   = "${local.name_prefix}-tpu-sa-${local.name_suffix}"
  display_name = "TPU Inference Service Account"
  description  = "Service account for Ironwood TPU inference operations"
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for TPU service account with minimal required permissions
resource "google_project_iam_member" "tpu_service_account_permissions" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/compute.instanceAdmin.v1",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/storage.objectViewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.tpu_service_account_email}"
  
  depends_on = [google_service_account.tpu_inference]
}

# Create VPC network for TPU resources with optimized configuration
resource "google_compute_network" "tpu_network" {
  name                    = "${local.name_prefix}-network-${local.name_suffix}"
  auto_create_subnetworks = false
  mtu                     = 1500
  description             = "VPC network for TPU inference infrastructure"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet with sufficient IP range for TPU pods
resource "google_compute_subnetwork" "tpu_subnet" {
  name                     = "${local.name_prefix}-subnet-${local.name_suffix}"
  ip_cidr_range           = "10.0.0.0/16"
  region                  = var.region
  network                 = google_compute_network.tpu_network.id
  private_ip_google_access = true
  description             = "Subnet for TPU inference infrastructure"
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for TPU communication and load balancer health checks
resource "google_compute_firewall" "tpu_internal" {
  name    = "${local.name_prefix}-tpu-internal-${local.name_suffix}"
  network = google_compute_network.tpu_network.name
  
  description = "Allow internal communication between TPU resources"
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "8888", "22"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = ["10.0.0.0/16"]
  target_tags   = ["tpu-inference"]
}

resource "google_compute_firewall" "load_balancer_health_check" {
  name    = "${local.name_prefix}-lb-health-${local.name_suffix}"
  network = google_compute_network.tpu_network.name
  
  description = "Allow health checks from Google Cloud Load Balancer"
  
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  
  # Google Cloud Load Balancer health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["tpu-inference"]
}

# Create NAT gateway for outbound internet access from TPU pods
resource "google_compute_router" "tpu_router" {
  name    = "${local.name_prefix}-router-${local.name_suffix}"
  region  = var.region
  network = google_compute_network.tpu_network.id
  
  description = "Cloud Router for TPU NAT gateway"
}

resource "google_compute_router_nat" "tpu_nat" {
  name   = "${local.name_prefix}-nat-${local.name_suffix}"
  router = google_compute_router.tpu_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Create small TPU pod (v7-256) for lightweight inference workloads
resource "google_tpu_v2_vm" "small_tpu" {
  count = var.enable_small_tpu ? 1 : 0
  
  name = "${local.name_prefix}-small-${local.name_suffix}"
  zone = var.zone
  
  accelerator_type   = "v7-256"
  runtime_version    = var.tpu_version
  service_account    = local.tpu_service_account_email
  description        = "Ironwood TPU v7-256 for lightweight AI inference"
  
  network_config {
    network    = google_compute_network.tpu_network.id
    subnetwork = google_compute_subnetwork.tpu_subnet.id
  }
  
  scheduling_config {
    preemptible = false
  }
  
  shielded_instance_config {
    enable_secure_boot = true
  }
  
  labels = local.common_labels
  
  tags = ["tpu-inference", "small-tpu"]
  
  depends_on = [
    google_project_iam_member.tpu_service_account_permissions,
    google_compute_router_nat.tpu_nat
  ]
}

# Create medium TPU pod (v7-1024) for standard inference workloads
resource "google_tpu_v2_vm" "medium_tpu" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name = "${local.name_prefix}-medium-${local.name_suffix}"
  zone = var.zone
  
  accelerator_type   = "v7-1024"
  runtime_version    = var.tpu_version
  service_account    = local.tpu_service_account_email
  description        = "Ironwood TPU v7-1024 for standard AI inference"
  
  network_config {
    network    = google_compute_network.tpu_network.id
    subnetwork = google_compute_subnetwork.tpu_subnet.id
  }
  
  scheduling_config {
    preemptible = false
  }
  
  shielded_instance_config {
    enable_secure_boot = true
  }
  
  labels = local.common_labels
  
  tags = ["tpu-inference", "medium-tpu"]
  
  depends_on = [
    google_project_iam_member.tpu_service_account_permissions,
    google_compute_router_nat.tpu_nat
  ]
}

# Create large TPU pod (v7-9216) for high-throughput inference workloads
resource "google_tpu_v2_vm" "large_tpu" {
  count = var.enable_large_tpu ? 1 : 0
  
  name = "${local.name_prefix}-large-${local.name_suffix}"
  zone = var.zone
  
  accelerator_type   = "v7-9216"
  runtime_version    = var.tpu_version
  service_account    = local.tpu_service_account_email
  description        = "Ironwood TPU v7-9216 for high-throughput AI inference"
  
  network_config {
    network    = google_compute_network.tpu_network.id
    subnetwork = google_compute_subnetwork.tpu_subnet.id
  }
  
  scheduling_config {
    preemptible = false
  }
  
  shielded_instance_config {
    enable_secure_boot = true
  }
  
  labels = local.common_labels
  
  tags = ["tpu-inference", "large-tpu"]
  
  depends_on = [
    google_project_iam_member.tpu_service_account_permissions,
    google_compute_router_nat.tpu_nat
  ]
}

# Create Vertex AI model for deployment across TPU endpoints
resource "google_vertex_ai_model" "inference_model" {
  name         = "${local.name_prefix}-model-${local.name_suffix}"
  display_name = "${var.model_name} Optimized for Ironwood TPU"
  description  = "AI model optimized for inference on Ironwood TPU architecture"
  region       = var.region
  
  container_spec {
    image_uri = "gcr.io/vertex-ai/prediction/pytorch-gpu.1-13:latest"
    
    env {
      name  = "MODEL_NAME"
      value = var.model_name
    }
    
    env {
      name  = "TPU_OPTIMIZATION"
      value = "ironwood-v7"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Vertex AI endpoints for different TPU tiers
resource "google_vertex_ai_endpoint" "small_endpoint" {
  count = var.enable_small_tpu ? 1 : 0
  
  name         = "${local.name_prefix}-endpoint-small-${local.name_suffix}"
  display_name = "Small TPU Inference Endpoint"
  description  = "Vertex AI endpoint for small TPU pod inference"
  location     = var.region
  
  labels = local.common_labels
  
  depends_on = [google_vertex_ai_model.inference_model]
}

resource "google_vertex_ai_endpoint" "medium_endpoint" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name         = "${local.name_prefix}-endpoint-medium-${local.name_suffix}"
  display_name = "Medium TPU Inference Endpoint"
  description  = "Vertex AI endpoint for medium TPU pod inference"
  location     = var.region
  
  labels = local.common_labels
  
  depends_on = [google_vertex_ai_model.inference_model]
}

resource "google_vertex_ai_endpoint" "large_endpoint" {
  count = var.enable_large_tpu ? 1 : 0
  
  name         = "${local.name_prefix}-endpoint-large-${local.name_suffix}"
  display_name = "Large TPU Inference Endpoint"
  description  = "Vertex AI endpoint for large TPU pod inference"
  location     = var.region
  
  labels = local.common_labels
  
  depends_on = [google_vertex_ai_model.inference_model]
}

# Create Redis cache for inference optimization and response caching
resource "google_redis_instance" "inference_cache" {
  count = var.enable_redis_cache ? 1 : 0
  
  name           = "${local.name_prefix}-cache-${local.name_suffix}"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  
  tier                    = "STANDARD_HA"
  redis_version          = "REDIS_7_0"
  display_name           = "Inference Cache"
  reserved_ip_range      = "192.168.0.0/28"
  connect_mode           = "PRIVATE_SERVICE_ACCESS"
  authorized_network     = google_compute_network.tpu_network.id
  
  auth_enabled           = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create health check for TPU inference endpoints
resource "google_compute_health_check" "tpu_health_check" {
  name                = "${local.name_prefix}-health-check-${local.name_suffix}"
  description         = "Health check for TPU inference endpoints"
  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port         = 8080
    request_path = "/health"
  }
  
  log_config {
    enable = true
  }
}

# Create backend services for different TPU tiers with intelligent routing
resource "google_compute_backend_service" "small_backend" {
  count = var.enable_small_tpu ? 1 : 0
  
  name                    = "${local.name_prefix}-backend-small-${local.name_suffix}"
  description             = "Backend service for small TPU inference"
  protocol                = "HTTP"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 30
  enable_cdn              = var.enable_cdn
  
  health_checks = [google_compute_health_check.tpu_health_check.id]
  
  backend {
    group           = google_compute_instance_group.small_tpu_group[0].id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                 = 3600
    client_ttl                  = 3600
    max_ttl                     = 86400
    negative_caching            = true
    serve_while_stale           = 86400
  }
  
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_backend_service" "medium_backend" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name                    = "${local.name_prefix}-backend-medium-${local.name_suffix}"
  description             = "Backend service for medium TPU inference"
  protocol                = "HTTP"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 60
  enable_cdn              = var.enable_cdn
  
  health_checks = [google_compute_health_check.tpu_health_check.id]
  
  backend {
    group           = google_compute_instance_group.medium_tpu_group[0].id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_backend_service" "large_backend" {
  count = var.enable_large_tpu ? 1 : 0
  
  name                    = "${local.name_prefix}-backend-large-${local.name_suffix}"
  description             = "Backend service for large TPU inference"
  protocol                = "HTTP"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 120
  enable_cdn              = false
  
  health_checks = [google_compute_health_check.tpu_health_check.id]
  
  backend {
    group           = google_compute_instance_group.large_tpu_group[0].id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Create instance groups for TPU backend services
resource "google_compute_instance_group" "small_tpu_group" {
  count = var.enable_small_tpu ? 1 : 0
  
  name        = "${local.name_prefix}-small-group-${local.name_suffix}"
  description = "Instance group for small TPU pods"
  zone        = var.zone
  network     = google_compute_network.tpu_network.id
  
  named_port {
    name = "http"
    port = "8080"
  }
}

resource "google_compute_instance_group" "medium_tpu_group" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name        = "${local.name_prefix}-medium-group-${local.name_suffix}"
  description = "Instance group for medium TPU pods"
  zone        = var.zone
  network     = google_compute_network.tpu_network.id
  
  named_port {
    name = "http"
    port = "8080"
  }
}

resource "google_compute_instance_group" "large_tpu_group" {
  count = var.enable_large_tpu ? 1 : 0
  
  name        = "${local.name_prefix}-large-group-${local.name_suffix}"
  description = "Instance group for large TPU pods"
  zone        = var.zone
  network     = google_compute_network.tpu_network.id
  
  named_port {
    name = "http"
    port = "8080"
  }
}

# Create URL map for intelligent request routing
resource "google_compute_url_map" "ai_inference_lb" {
  name            = "${local.name_prefix}-url-map-${local.name_suffix}"
  description     = "URL map for AI inference load balancing"
  default_service = var.enable_medium_tpu ? google_compute_backend_service.medium_backend[0].id : (var.enable_small_tpu ? google_compute_backend_service.small_backend[0].id : null)
  
  # Route simple queries to small TPU pods
  dynamic "path_matcher" {
    for_each = var.enable_small_tpu ? [1] : []
    content {
      name            = "simple-inference"
      default_service = google_compute_backend_service.small_backend[0].id
      
      path_rule {
        paths   = ["/simple/*", "/basic/*", "/quick/*"]
        service = google_compute_backend_service.small_backend[0].id
      }
    }
  }
  
  # Route complex queries to large TPU pods
  dynamic "path_matcher" {
    for_each = var.enable_large_tpu ? [1] : []
    content {
      name            = "complex-inference"
      default_service = google_compute_backend_service.large_backend[0].id
      
      path_rule {
        paths   = ["/complex/*", "/advanced/*", "/reasoning/*"]
        service = google_compute_backend_service.large_backend[0].id
      }
    }
  }
  
  host_rule {
    hosts        = ["*"]
    path_matcher = "simple-inference"
  }
}

# Create HTTP proxy for the load balancer
resource "google_compute_target_http_proxy" "ai_inference_proxy" {
  name    = "${local.name_prefix}-proxy-${local.name_suffix}"
  url_map = google_compute_url_map.ai_inference_lb.id
}

# Reserve global IP address for the load balancer
resource "google_compute_global_address" "ai_inference_ip" {
  name         = "${local.name_prefix}-ip-${local.name_suffix}"
  description  = "Global IP address for AI inference load balancer"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# Create global forwarding rule
resource "google_compute_global_forwarding_rule" "ai_inference_forwarding_rule" {
  name                  = "${local.name_prefix}-forwarding-rule-${local.name_suffix}"
  description           = "Global forwarding rule for AI inference"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.ai_inference_ip.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.ai_inference_proxy.id
}

# Create SSL certificate and HTTPS load balancer if SSL is enabled
resource "google_compute_managed_ssl_certificate" "ai_inference_ssl" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name = "${local.name_prefix}-ssl-cert-${local.name_suffix}"
  
  managed {
    domains = var.ssl_certificate_domains
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "ai_inference_https_proxy" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name             = "${local.name_prefix}-https-proxy-${local.name_suffix}"
  url_map          = google_compute_url_map.ai_inference_lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ai_inference_ssl[0].id]
}

resource "google_compute_global_forwarding_rule" "ai_inference_https_forwarding_rule" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name                  = "${local.name_prefix}-https-forwarding-rule-${local.name_suffix}"
  description           = "HTTPS forwarding rule for AI inference"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.ai_inference_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.ai_inference_https_proxy[0].id
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "tpu_analytics" {
  count = var.enable_bigquery_analytics ? 1 : 0
  
  dataset_id                 = "${replace(local.name_prefix, "-", "_")}_analytics_${local.name_suffix}"
  friendly_name             = "TPU Inference Analytics"
  description               = "Dataset for TPU inference performance analytics"
  location                  = var.bigquery_dataset_location
  default_table_expiration_ms = 2592000000 # 30 days
  
  labels = local.common_labels
  
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }
  
  access {
    role          = "WRITER"
    user_by_email = local.tpu_service_account_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Get current user info for BigQuery access
data "google_client_openid_userinfo" "me" {}

# Create Pub/Sub topic for real-time metrics streaming
resource "google_pubsub_topic" "tpu_metrics_stream" {
  count = var.enable_monitoring ? 1 : 0
  
  name = "${local.name_prefix}-metrics-stream-${local.name_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for BigQuery streaming
resource "google_pubsub_subscription" "tpu_analytics_sub" {
  count = var.enable_monitoring && var.enable_bigquery_analytics ? 1 : 0
  
  name  = "${local.name_prefix}-analytics-sub-${local.name_suffix}"
  topic = google_pubsub_topic.tpu_metrics_stream[0].name
  
  ack_deadline_seconds = 20
  
  bigquery_config {
    table = "${google_bigquery_dataset.tpu_analytics[0].dataset_id}.inference_metrics"
  }
  
  depends_on = [google_bigquery_dataset.tpu_analytics]
}

# Create notification channel for monitoring alerts
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for TPU performance
resource "google_monitoring_dashboard" "tpu_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "TPU Inference Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "TPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\""
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
  
  depends_on = [google_project_service.required_apis]
}

# Create budget and budget alert
resource "google_billing_budget" "tpu_budget" {
  count = var.enable_monitoring ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
  display_name    = "TPU Inference Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = var.budget_threshold_percent
    spend_basis      = "CURRENT_SPEND"
  }
  
  dynamic "all_updates_rule" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      monitoring_notification_channels = [google_monitoring_notification_channel.email[0].name]
      disable_default_iam_recipients   = false
    }
  }
}

# Get billing account information
data "google_billing_account" "account" {
  billing_account = data.google_project.project.billing_account
}

data "google_project" "project" {
  project_id = var.project_id
}

# Create autoscaling policies for TPU endpoints (using instance groups)
resource "google_compute_autoscaler" "small_tpu_autoscaler" {
  count = var.enable_small_tpu ? 1 : 0
  
  name   = "${local.name_prefix}-small-autoscaler-${local.name_suffix}"
  zone   = var.zone
  target = google_compute_instance_group_manager.small_tpu_manager[0].id
  
  autoscaling_policy {
    max_replicas    = var.max_replicas_small
    min_replicas    = var.min_replicas_small
    cooldown_period = 300
    
    cpu_utilization {
      target = var.auto_scaling_target_cpu_utilization
    }
  }
}

resource "google_compute_autoscaler" "medium_tpu_autoscaler" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name   = "${local.name_prefix}-medium-autoscaler-${local.name_suffix}"
  zone   = var.zone
  target = google_compute_instance_group_manager.medium_tpu_manager[0].id
  
  autoscaling_policy {
    max_replicas    = var.max_replicas_medium
    min_replicas    = var.min_replicas_medium
    cooldown_period = 300
    
    cpu_utilization {
      target = var.auto_scaling_target_cpu_utilization
    }
  }
}

resource "google_compute_autoscaler" "large_tpu_autoscaler" {
  count = var.enable_large_tpu ? 1 : 0
  
  name   = "${local.name_prefix}-large-autoscaler-${local.name_suffix}"
  zone   = var.zone
  target = google_compute_instance_group_manager.large_tpu_manager[0].id
  
  autoscaling_policy {
    max_replicas    = var.max_replicas_large
    min_replicas    = var.min_replicas_large
    cooldown_period = 600
    
    cpu_utilization {
      target = var.auto_scaling_target_cpu_utilization
    }
  }
}

# Create instance group managers for autoscaling
resource "google_compute_instance_group_manager" "small_tpu_manager" {
  count = var.enable_small_tpu ? 1 : 0
  
  name = "${local.name_prefix}-small-manager-${local.name_suffix}"
  zone = var.zone
  
  base_instance_name = "${local.name_prefix}-small"
  target_size        = var.min_replicas_small
  
  version {
    instance_template = google_compute_instance_template.tpu_template.id
  }
  
  named_port {
    name = "http"
    port = 8080
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.tpu_health_check.id
    initial_delay_sec = 300
  }
}

resource "google_compute_instance_group_manager" "medium_tpu_manager" {
  count = var.enable_medium_tpu ? 1 : 0
  
  name = "${local.name_prefix}-medium-manager-${local.name_suffix}"
  zone = var.zone
  
  base_instance_name = "${local.name_prefix}-medium"
  target_size        = var.min_replicas_medium
  
  version {
    instance_template = google_compute_instance_template.tpu_template.id
  }
  
  named_port {
    name = "http"
    port = 8080
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.tpu_health_check.id
    initial_delay_sec = 300
  }
}

resource "google_compute_instance_group_manager" "large_tpu_manager" {
  count = var.enable_large_tpu ? 1 : 0
  
  name = "${local.name_prefix}-large-manager-${local.name_suffix}"
  zone = var.zone
  
  base_instance_name = "${local.name_prefix}-large"
  target_size        = var.min_replicas_large
  
  version {
    instance_template = google_compute_instance_template.tpu_template.id
  }
  
  named_port {
    name = "http"
    port = 8080
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.tpu_health_check.id
    initial_delay_sec = 600
  }
}

# Create instance template for TPU inference servers
resource "google_compute_instance_template" "tpu_template" {
  name_prefix  = "${local.name_prefix}-template-"
  description  = "Instance template for TPU inference servers"
  machine_type = "n1-standard-4"
  
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-ssd"
  }
  
  network_interface {
    network    = google_compute_network.tpu_network.id
    subnetwork = google_compute_subnetwork.tpu_subnet.id
  }
  
  service_account {
    email  = local.tpu_service_account_email
    scopes = ["cloud-platform"]
  }
  
  tags = ["tpu-inference"]
  
  labels = local.common_labels
  
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y python3 python3-pip docker.io
    
    # Install TPU inference server
    pip3 install tensorflow torch
    
    # Configure inference server
    cat > /opt/inference_server.py << 'PYTHON_EOF'
import http.server
import socketserver

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy"}')
        else:
            super().do_GET()

PORT = 8080
with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
    httpd.serve_forever()
PYTHON_EOF
    
    # Start inference server
    python3 /opt/inference_server.py &
  EOF
  
  lifecycle {
    create_before_destroy = true
  }
}