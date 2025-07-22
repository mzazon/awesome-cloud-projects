# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  bucket_name = var.bucket_name != null ? var.bucket_name : "pwa-assets-${random_id.suffix.hex}"
  
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "progressive-web-application-deployment-build-kubernetes-engine"
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for GKE clusters
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.vpc_network.id
  region        = var.region
  
  # Secondary IP ranges for GKE
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
  
  private_ip_google_access = true
}

# Create Cloud NAT for private nodes
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Create GKE Blue Environment Cluster
resource "google_container_cluster" "blue_cluster" {
  name     = var.cluster_name_blue
  location = var.region
  
  # Network configuration
  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Cluster configuration
  deletion_protection      = false
  enable_autopilot        = false
  enable_l4_ilb_subsetting = true
  
  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }
  
  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Monitoring and logging
  monitoring_service = var.enable_monitoring ? var.monitoring_service : "none"
  logging_service    = var.enable_logging ? var.logging_service : "none"
  
  # Backup configuration
  dynamic "backup_config" {
    for_each = var.enable_backup ? [1] : []
    content {
      enabled                     = true
      backup_retain_days         = var.backup_retention_days
      selected_applications {
        namespaced_names {
          name      = "pwa-demo-app"
          namespace = "default"
        }
      }
    }
  }
  
  # Security configuration
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  
  # Master authorized networks
  master_authorized_networks_config {
    # Allow access from anywhere (adjust for production)
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }
  
  # Cluster autoscaling
  cluster_autoscaling {
    enabled = true
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 100
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 1
      maximum       = 1000
    }
  }
  
  # Addons
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = !var.enable_network_policy
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  
  # Node locations
  node_locations = [var.zone]
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "blue"
    cluster     = "blue"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.subnet,
    google_compute_router_nat.nat
  ]
}

# Create node pool for Blue cluster
resource "google_container_node_pool" "blue_nodes" {
  name       = "${var.cluster_name_blue}-nodes"
  location   = var.region
  cluster    = google_container_cluster.blue_cluster.name
  node_count = var.node_count
  
  # Autoscaling
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  
  # Node configuration
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    
    # Service account
    service_account = google_service_account.gke_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Security
    image_type = "COS_CONTAINERD"
    
    # Labels
    labels = merge(local.common_labels, {
      environment = "blue"
      node-pool   = "blue-nodes"
    })
    
    # Taints
    taint {
      key    = "environment"
      value  = "blue"
      effect = "NO_SCHEDULE"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  depends_on = [google_container_cluster.blue_cluster]
}

# Create GKE Green Environment Cluster
resource "google_container_cluster" "green_cluster" {
  name     = var.cluster_name_green
  location = var.region
  
  # Network configuration
  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Cluster configuration
  deletion_protection      = false
  enable_autopilot        = false
  enable_l4_ilb_subsetting = true
  
  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }
  
  # Network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Monitoring and logging
  monitoring_service = var.enable_monitoring ? var.monitoring_service : "none"
  logging_service    = var.enable_logging ? var.logging_service : "none"
  
  # Backup configuration
  dynamic "backup_config" {
    for_each = var.enable_backup ? [1] : []
    content {
      enabled                     = true
      backup_retain_days         = var.backup_retention_days
      selected_applications {
        namespaced_names {
          name      = "pwa-demo-app"
          namespace = "default"
        }
      }
    }
  }
  
  # Security configuration
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  
  # Master authorized networks
  master_authorized_networks_config {
    # Allow access from anywhere (adjust for production)
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }
  
  # Cluster autoscaling
  cluster_autoscaling {
    enabled = true
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 100
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 1
      maximum       = 1000
    }
  }
  
  # Addons
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = !var.enable_network_policy
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  
  # Node locations
  node_locations = [var.zone]
  
  # Resource labels
  resource_labels = merge(local.common_labels, {
    environment = "green"
    cluster     = "green"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.subnet,
    google_compute_router_nat.nat
  ]
}

# Create node pool for Green cluster
resource "google_container_node_pool" "green_nodes" {
  name       = "${var.cluster_name_green}-nodes"
  location   = var.region
  cluster    = google_container_cluster.green_cluster.name
  node_count = var.node_count
  
  # Autoscaling
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  
  # Node configuration
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    
    # Service account
    service_account = google_service_account.gke_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Security
    image_type = "COS_CONTAINERD"
    
    # Labels
    labels = merge(local.common_labels, {
      environment = "green"
      node-pool   = "green-nodes"
    })
    
    # Taints
    taint {
      key    = "environment"
      value  = "green"
      effect = "NO_SCHEDULE"
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  depends_on = [google_container_cluster.green_cluster]
}

# Create service account for GKE nodes
resource "google_service_account" "gke_service_account" {
  account_id   = "${var.app_name}-gke-sa"
  display_name = "GKE Service Account for ${var.app_name}"
  description  = "Service account for GKE nodes in blue-green deployment"
}

# IAM bindings for GKE service account
resource "google_project_iam_member" "gke_service_account_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_service_account.email}"
}

# Create Cloud Storage bucket for PWA assets
resource "google_storage_bucket" "pwa_assets" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Enable versioning
  versioning {
    enabled = true
  }
  
  # CORS configuration for PWA
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }
  
  # Lifecycle rule for old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Source Repository
resource "google_sourcerepo_repository" "pwa_repo" {
  name = var.source_repo_name
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Build
resource "google_service_account" "cloud_build_sa" {
  account_id   = "${var.app_name}-cloudbuild-sa"
  display_name = "Cloud Build Service Account for ${var.app_name}"
  description  = "Service account for Cloud Build CI/CD pipeline"
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloud_build_sa_roles" {
  for_each = toset([
    "roles/container.developer",
    "roles/storage.admin",
    "roles/source.admin",
    "roles/cloudbuild.builds.builder",
    "roles/logging.logWriter",
    "roles/artifactregistry.writer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# Create Cloud Build trigger
resource "google_cloudbuild_trigger" "pwa_build_trigger" {
  name        = "${var.app_name}-build-trigger"
  description = "PWA deployment trigger for master branch"
  
  # Repository configuration
  trigger_template {
    repo_name   = google_sourcerepo_repository.pwa_repo.name
    branch_name = "master"
  }
  
  # Build configuration
  filename = var.build_trigger_filename
  
  # Substitutions
  substitutions = {
    _REGION        = var.region
    _CLUSTER_BLUE  = var.cluster_name_blue
    _CLUSTER_GREEN = var.cluster_name_green
    _APP_NAME      = var.app_name
    _BUCKET_NAME   = google_storage_bucket.pwa_assets.name
  }
  
  # Service account
  service_account = google_service_account.cloud_build_sa.id
  
  depends_on = [
    google_project_service.required_apis,
    google_sourcerepo_repository.pwa_repo
  ]
}

# Create global static IP for load balancer
resource "google_compute_global_address" "static_ip" {
  name         = var.static_ip_name
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  
  depends_on = [google_project_service.required_apis]
}

# Create SSL certificate
resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = "${var.app_name}-ssl-cert"
  
  managed {
    domains = var.ssl_certificate_domains
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create firewall rules for GKE
resource "google_compute_firewall" "gke_firewall" {
  name    = "${var.network_name}-gke-firewall"
  network = google_compute_network.vpc_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
  
  depends_on = [google_compute_network.vpc_network]
}

# Create Cloud Monitoring dashboard
resource "google_monitoring_dashboard" "pwa_dashboard" {
  dashboard_json = jsonencode({
    displayName = "PWA Blue-Green Deployment Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "GKE Cluster CPU Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/cpu/core_usage_time\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Usage"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "GKE Cluster Memory Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/memory/used_bytes\""
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Memory Usage (Bytes)"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Logging sink for application logs
resource "google_logging_project_sink" "pwa_log_sink" {
  name        = "${var.app_name}-log-sink"
  description = "Log sink for PWA application logs"
  
  # Export all logs from GKE clusters
  filter = "resource.type=\"k8s_container\" AND resource.labels.cluster_name=~\"${var.cluster_name_blue}|${var.cluster_name_green}\""
  
  # Destination: Cloud Storage bucket
  destination = "storage.googleapis.com/${google_storage_bucket.pwa_assets.name}"
  
  # Unique writer identity
  unique_writer_identity = true
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.pwa_assets
  ]
}

# Grant the log sink writer permissions to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.pwa_assets.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.pwa_log_sink.writer_identity
}

# Create notification channel for alerting
resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for cluster health
resource "google_monitoring_alert_policy" "cluster_health_alert" {
  display_name = "GKE Cluster Health Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Node CPU utilization is too high"
    condition_threshold {
      filter         = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.email_channel.name
  ]
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.email_channel
  ]
}