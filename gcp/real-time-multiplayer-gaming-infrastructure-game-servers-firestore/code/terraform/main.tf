# main.tf
# Main Terraform configuration for GCP multiplayer gaming infrastructure
# This creates a complete real-time multiplayer gaming infrastructure using
# GKE with Agones, Cloud Firestore, Cloud Run, and Load Balancing

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix
  suffix             = random_id.suffix.hex
  gke_cluster_name   = var.gke_cluster_name != "" ? var.gke_cluster_name : "${var.game_name}-cluster-${local.suffix}"
  cloud_run_service  = var.cloud_run_service_name != "" ? var.cloud_run_service_name : "${var.game_name}-matchmaking-${local.suffix}"
  network_name       = var.network_name != "" ? var.network_name : "${var.game_name}-network-${local.suffix}"
  subnet_name        = var.subnet_name != "" ? var.subnet_name : "${var.game_name}-subnet-${local.suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    game        = var.game_name
    terraform   = "true"
  })
  
  # Required APIs for the gaming infrastructure
  required_apis = [
    "container.googleapis.com",          # Google Kubernetes Engine
    "gameservices.googleapis.com",       # Game Servers API
    "run.googleapis.com",               # Cloud Run
    "firestore.googleapis.com",         # Cloud Firestore
    "compute.googleapis.com",           # Compute Engine (for load balancer)
    "monitoring.googleapis.com",        # Cloud Monitoring
    "logging.googleapis.com",           # Cloud Logging
    "cloudbuild.googleapis.com"         # Cloud Build (for container builds)
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create VPC network for gaming infrastructure
resource "google_compute_network" "gaming_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for GKE cluster and game servers
resource "google_compute_subnetwork" "gaming_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.gaming_network.id
  project       = var.project_id
  
  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
  
  # Enable private Google access for nodes without external IPs
  private_ip_google_access = true
}

# Create Cloud NAT for private nodes to access external resources
resource "google_compute_router" "gaming_router" {
  name    = "${var.game_name}-router-${local.suffix}"
  region  = var.region
  network = google_compute_network.gaming_network.id
  project = var.project_id
}

resource "google_compute_router_nat" "gaming_nat" {
  name                               = "${var.game_name}-nat-${local.suffix}"
  router                            = google_compute_router.gaming_router.name
  region                            = var.region
  project                           = var.project_id
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Create GKE cluster optimized for gaming workloads
resource "google_container_cluster" "game_cluster" {
  name     = local.gke_cluster_name
  location = var.zone
  project  = var.project_id
  
  # Remove default node pool to create custom one
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = google_compute_network.gaming_network.name
  subnetwork = google_compute_subnetwork.gaming_subnet.name
  
  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Master authorized networks (adjust for production)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }
  
  # Enable network policy for security
  network_policy {
    enabled = true
  }
  
  # Enable pod security policy (if available)
  pod_security_policy_config {
    enabled = false # Deprecated in favor of Pod Security Standards
  }
  
  # Enable Shielded GKE nodes
  enable_shielded_nodes = true
  
  # Workload Identity for secure access to Google Cloud services
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Resource labels
  resource_labels = local.common_labels
  
  # Maintenance policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Enable monitoring and logging
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    
    managed_prometheus {
      enabled = var.enable_monitoring
    }
  }
  
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.gaming_subnet
  ]
}

# Create node pool optimized for game servers
resource "google_container_node_pool" "game_nodes" {
  name       = "game-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.game_cluster.name
  project    = var.project_id
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.gke_min_node_count
    max_node_count = var.gke_max_node_count
  }
  
  # Initial node count
  initial_node_count = var.gke_node_count
  
  # Node configuration
  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_disk_size
    disk_type    = var.gke_disk_type
    
    # Use the default service account with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Security configurations
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Workload Identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Resource labels
    labels = merge(local.common_labels, {
      node-pool = "game-servers"
    })
    
    # Node taints for game server workloads (optional)
    # taint {
    #   key    = "game-server"
    #   value  = "true"
    #   effect = "NO_SCHEDULE"
    # }
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  # Network configuration
  network_config {
    create_pod_range     = false
    enable_private_nodes = var.enable_private_nodes
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.game_name}-gke-nodes-${local.suffix}"
  display_name = "GKE Nodes Service Account for ${var.game_name}"
  project      = var.project_id
}

# IAM binding for GKE node service account
resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer", # For pulling container images
    "roles/artifactregistry.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Install Agones using Helm
resource "helm_release" "agones" {
  name       = "agones"
  repository = "https://agones.dev/chart/stable"
  chart      = "agones"
  version    = var.agones_version
  namespace  = "agones-system"
  
  create_namespace = true
  
  # Agones configuration values
  set {
    name  = "gameservers.minPort"
    value = var.agones_gameserver_min_port
  }
  
  set {
    name  = "gameservers.maxPort"
    value = var.agones_gameserver_max_port
  }
  
  set {
    name  = "gameservers.podPreserveUnknownFields"
    value = "false"
  }
  
  # Enable metrics for monitoring
  set {
    name  = "agones.metrics.prometheusEnabled"
    value = "true"
  }
  
  set {
    name  = "agones.metrics.prometheusServiceDiscovery"
    value = "true"
  }
  
  # Security settings
  set {
    name  = "agones.controller.persistentLogs"
    value = "true"
  }
  
  depends_on = [
    google_container_cluster.game_cluster,
    google_container_node_pool.game_nodes
  ]
}

# Create Kubernetes namespace for game servers
resource "kubernetes_namespace" "game_servers" {
  metadata {
    name = "game-servers"
    
    labels = {
      name = "game-servers"
    }
  }
  
  depends_on = [helm_release.agones]
}

# Deploy game server fleet
resource "kubernetes_manifest" "game_server_fleet" {
  manifest = {
    apiVersion = "agones.dev/v1"
    kind       = "Fleet"
    metadata = {
      name      = "simple-game-server-fleet"
      namespace = kubernetes_namespace.game_servers.metadata[0].name
    }
    spec = {
      replicas = var.gameserver_fleet_replicas
      template = {
        spec = {
          ports = [{
            name          = "default"
            containerPort = 7654
            protocol      = "UDP"
          }]
          health = {
            disabled             = false
            initialDelaySeconds  = 5
            periodSeconds        = 5
            failureThreshold     = 3
          }
          template = {
            spec = {
              containers = [{
                name  = "simple-game-server"
                image = var.gameserver_image
                resources = {
                  requests = {
                    memory = var.gameserver_memory_request
                    cpu    = var.gameserver_cpu_request
                  }
                  limits = {
                    memory = var.gameserver_memory_limit
                    cpu    = var.gameserver_cpu_limit
                  }
                }
              }]
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    helm_release.agones,
    kubernetes_namespace.game_servers
  ]
}

# Create Cloud Firestore database for real-time game state
resource "google_firestore_database" "game_database" {
  project     = var.project_id
  name        = "${var.game_name}-db-${local.suffix}"
  location_id = var.firestore_location
  type        = var.firestore_type
  
  # Concurrency mode for better performance
  concurrency_mode = "OPTIMISTIC"
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Run matchmaking service
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.game_name}-run-sa-${local.suffix}"
  display_name = "Cloud Run Service Account for ${var.game_name}"
  project      = var.project_id
}

# IAM bindings for Cloud Run service account
resource "google_project_iam_member" "cloud_run_sa" {
  for_each = toset([
    "roles/firestore.user",           # Access to Firestore
    "roles/container.developer",      # Access to GKE for game server allocation
    "roles/logging.logWriter",        # Write logs
    "roles/monitoring.metricWriter"   # Write metrics
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Cloud Run service for matchmaking
resource "google_cloud_run_service" "matchmaking_service" {
  name     = local.cloud_run_service
  location = var.region
  project  = var.project_id
  
  template {
    metadata {
      labels = local.common_labels
      
      annotations = {
        "autoscaling.knative.dev/maxScale"         = var.cloud_run_max_instances
        "autoscaling.knative.dev/minScale"         = var.cloud_run_min_instances
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/cpu-throttling"        = "false"
      }
    }
    
    spec {
      service_account_name = google_service_account.cloud_run_sa.email
      
      containers {
        image = var.cloud_run_image
        
        ports {
          container_port = 8080
        }
        
        resources {
          limits = {
            cpu    = var.cloud_run_cpu
            memory = var.cloud_run_memory
          }
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "FIRESTORE_DATABASE"
          value = google_firestore_database.game_database.name
        }
        
        env {
          name  = "GKE_CLUSTER_NAME"
          value = google_container_cluster.game_cluster.name
        }
        
        env {
          name  = "GKE_CLUSTER_ZONE"
          value = var.zone
        }
      }
      
      timeout_seconds = 60
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.game_database
  ]
}

# IAM policy for Cloud Run service (allow public access)
resource "google_cloud_run_service_iam_binding" "public_access" {
  location = google_cloud_run_service.matchmaking_service.location
  project  = google_cloud_run_service.matchmaking_service.project
  service  = google_cloud_run_service.matchmaking_service.name
  role     = "roles/run.invoker"
  
  members = [
    "allUsers"
  ]
}

# Global HTTP Load Balancer (if enabled)
resource "google_compute_backend_service" "game_backend" {
  count   = var.enable_global_load_balancer ? 1 : 0
  name    = "${var.game_name}-backend-${local.suffix}"
  project = var.project_id
  
  protocol    = "HTTP"
  timeout_sec = 30
  
  # Enable Cloud CDN for static content
  enable_cdn = true
  
  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg[0].id
  }
  
  log_config {
    enable      = var.enable_logging
    sample_rate = 1.0
  }
}

# Network Endpoint Group for Cloud Run
resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  count   = var.enable_global_load_balancer ? 1 : 0
  name    = "${var.game_name}-neg-${local.suffix}"
  project = var.project_id
  region  = var.region
  
  network_endpoint_type = "SERVERLESS"
  
  cloud_run {
    service = google_cloud_run_service.matchmaking_service.name
  }
}

# URL Map for load balancer
resource "google_compute_url_map" "game_url_map" {
  count   = var.enable_global_load_balancer ? 1 : 0
  name    = "${var.game_name}-urlmap-${local.suffix}"
  project = var.project_id
  
  default_service = google_compute_backend_service.game_backend[0].id
}

# HTTP(S) Target Proxy
resource "google_compute_target_http_proxy" "game_proxy" {
  count   = var.enable_global_load_balancer && !var.enable_ssl ? 1 : 0
  name    = "${var.game_name}-proxy-${local.suffix}"
  project = var.project_id
  url_map = google_compute_url_map.game_url_map[0].id
}

# HTTPS Target Proxy (if SSL is enabled)
resource "google_compute_target_https_proxy" "game_https_proxy" {
  count   = var.enable_global_load_balancer && var.enable_ssl ? 1 : 0
  name    = "${var.game_name}-https-proxy-${local.suffix}"
  project = var.project_id
  url_map = google_compute_url_map.game_url_map[0].id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.game_ssl[0].id
  ]
}

# Managed SSL Certificate (if SSL is enabled)
resource "google_compute_managed_ssl_certificate" "game_ssl" {
  count   = var.enable_global_load_balancer && var.enable_ssl ? 1 : 0
  name    = "${var.game_name}-ssl-${local.suffix}"
  project = var.project_id
  
  managed {
    domains = var.ssl_certificate_domains
  }
}

# Global Forwarding Rule for HTTP
resource "google_compute_global_forwarding_rule" "game_forwarding_rule" {
  count   = var.enable_global_load_balancer && !var.enable_ssl ? 1 : 0
  name    = "${var.game_name}-forwarding-rule-${local.suffix}"
  project = var.project_id
  
  port_range = "80"
  target     = google_compute_target_http_proxy.game_proxy[0].id
}

# Global Forwarding Rule for HTTPS
resource "google_compute_global_forwarding_rule" "game_https_forwarding_rule" {
  count   = var.enable_global_load_balancer && var.enable_ssl ? 1 : 0
  name    = "${var.game_name}-https-forwarding-rule-${local.suffix}"
  project = var.project_id
  
  port_range = "443"
  target     = google_compute_target_https_proxy.game_https_proxy[0].id
}

# Firewall rule to allow health checks
resource "google_compute_firewall" "allow_health_checks" {
  count   = var.enable_global_load_balancer ? 1 : 0
  name    = "${var.game_name}-allow-health-checks-${local.suffix}"
  project = var.project_id
  network = google_compute_network.gaming_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  
  # Google Cloud health check source ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]
  
  target_tags = ["cloud-run-health-check"]
}

# Create Firestore security rules
resource "null_resource" "firestore_rules" {
  triggers = {
    database_id = google_firestore_database.game_database.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      cat > firestore.rules << 'EOF'
      rules_version = '2';
      service cloud.firestore {
        match /databases/{database}/documents {
          match /games/{gameId} {
            allow read, write: if resource.data.players.hasAny([request.auth.uid]);
          }
          match /players/{playerId} {
            allow read, write: if request.auth.uid == playerId;
          }
        }
      }
      EOF
      
      gcloud firestore rules deploy firestore.rules \
        --database=${google_firestore_database.game_database.name} \
        --project=${var.project_id}
      
      rm -f firestore.rules
    EOT
  }
  
  depends_on = [google_firestore_database.game_database]
}