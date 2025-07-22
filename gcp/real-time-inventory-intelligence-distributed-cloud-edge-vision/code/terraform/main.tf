# Real-Time Inventory Intelligence Infrastructure with Google Distributed Cloud Edge
# This configuration deploys a complete inventory intelligence solution using edge computing and cloud AI

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    recipe      = "real-time-inventory-intelligence"
  })
  
  # Generate unique resource names
  db_instance_name = "${var.resource_prefix}-db-${random_id.suffix.hex}"
  bucket_name      = "${var.resource_prefix}-images-${random_id.suffix.hex}"
  cluster_name     = "${var.resource_prefix}-edge-cluster"
  service_account_name = "${var.resource_prefix}-edge-processor"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "vision.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud SQL instance for inventory data
resource "google_sql_database_instance" "inventory_db" {
  name             = local.db_instance_name
  database_version = "POSTGRES_14"
  region           = var.region
  
  settings {
    tier              = var.db_instance_tier
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size
    disk_autoresize   = true
    availability_type = "ZONAL"
    
    backup_configuration {
      enabled                        = true
      start_time                     = var.db_backup_start_time
      point_in_time_recovery_enabled = true
      location                       = var.region
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    ip_configuration {
      ipv4_enabled                                  = true
      private_network                              = var.enable_private_ip ? google_compute_network.vpc[0].id : null
      enable_private_path_for_google_cloud_services = var.enable_private_ip
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    user_labels = local.common_labels
  }
  
  deletion_protection = false
  
  depends_on = [google_project_service.required_apis]
  
  lifecycle {
    prevent_destroy = false
  }
}

# Create database within the Cloud SQL instance
resource "google_sql_database" "inventory_database" {
  name     = var.db_name
  instance = google_sql_database_instance.inventory_db.name
  charset  = "UTF8"
  collation = "en_US.UTF8"
}

# Set password for default postgres user
resource "google_sql_user" "postgres_user" {
  name     = "postgres"
  instance = google_sql_database_instance.inventory_db.name
  password = "SecureInventoryPass123!"
  type     = "BUILT_IN"
}

# Create VPC network for private connectivity (optional)
resource "google_compute_network" "vpc" {
  count                   = var.enable_private_ip ? 1 : 0
  name                    = "${var.resource_prefix}-vpc"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for the VPC
resource "google_compute_subnetwork" "subnet" {
  count         = var.enable_private_ip ? 1 : 0
  name          = "${var.resource_prefix}-subnet"
  network       = google_compute_network.vpc[0].id
  ip_cidr_range = "10.1.0.0/16"
  region        = var.region
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.2.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.3.0.0/16"
  }
}

# Create Cloud Storage bucket for image processing
resource "google_storage_bucket" "image_bucket" {
  name          = local.bucket_name
  location      = var.image_storage_location
  storage_class = var.image_storage_class
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.image_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for edge processing workloads
resource "google_service_account" "edge_processor" {
  account_id   = local.service_account_name
  display_name = "Inventory Edge Processor Service Account"
  description  = "Service account for edge inventory processing workloads"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "edge_processor_roles" {
  for_each = toset([
    "roles/ml.developer",
    "roles/cloudsql.client",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.edge_processor.email}"
}

# Grant Vision API service account access to the storage bucket
resource "google_storage_bucket_iam_member" "vision_bucket_access" {
  bucket = google_storage_bucket.image_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:vision@system.gserviceaccount.com"
}

# Create GKE cluster for edge processing (simulating Distributed Cloud Edge)
resource "google_container_cluster" "edge_cluster" {
  name     = local.cluster_name
  location = var.zone
  
  # Remove default node pool and create custom one
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = var.enable_private_ip ? google_compute_network.vpc[0].name : "default"
  subnetwork = var.enable_private_ip ? google_compute_subnetwork.subnet[0].name : null
  
  # Enable Workload Identity for secure service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Enable network policy for security
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Addons configuration
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = !var.enable_network_policy
    }
  }
  
  # Security configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  # Resource labels
  resource_labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create custom node pool for edge processing
resource "google_container_node_pool" "edge_nodes" {
  name       = "${local.cluster_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.edge_cluster.name
  node_count = var.edge_cluster_node_count
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }
  
  # Node configuration
  node_config {
    machine_type = var.edge_cluster_machine_type
    disk_size_gb = var.edge_cluster_disk_size
    disk_type    = "pd-ssd"
    
    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # OAuth scopes for service access
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    labels = local.common_labels
    
    tags = ["inventory-edge-node"]
  }
  
  # Update strategy
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Create Kubernetes service account for workload identity
resource "kubernetes_service_account" "edge_processor_k8s" {
  metadata {
    name      = "inventory-edge-processor"
    namespace = "default"
    
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.edge_processor.email
    }
    
    labels = local.common_labels
  }
  
  depends_on = [google_container_node_pool.edge_nodes]
}

# Bind Kubernetes service account to Google service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  count = var.enable_workload_identity ? 1 : 0
  
  service_account_id = google_service_account.edge_processor.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/inventory-edge-processor]"
}

# Deploy inventory processor application to the edge cluster
resource "kubernetes_deployment" "inventory_processor" {
  metadata {
    name      = "inventory-processor"
    namespace = "default"
    
    labels = merge(local.common_labels, {
      app = "inventory-processor"
    })
  }
  
  spec {
    replicas = var.processor_replicas
    
    selector {
      match_labels = {
        app = "inventory-processor"
      }
    }
    
    template {
      metadata {
        labels = merge(local.common_labels, {
          app = "inventory-processor"
        })
      }
      
      spec {
        service_account_name = kubernetes_service_account.edge_processor_k8s.metadata[0].name
        
        container {
          name  = "processor"
          image = var.processor_image
          
          env {
            name  = "PROJECT_ID"
            value = var.project_id
          }
          
          env {
            name  = "BUCKET_NAME"
            value = google_storage_bucket.image_bucket.name
          }
          
          env {
            name  = "DB_INSTANCE_CONNECTION"
            value = "${var.project_id}:${var.region}:${google_sql_database_instance.inventory_db.name}"
          }
          
          env {
            name  = "DB_NAME"
            value = google_sql_database.inventory_database.name
          }
          
          env {
            name  = "VISION_LOCATION"
            value = var.vision_api_location
          }
          
          resources {
            requests = {
              memory = var.processor_memory_request
              cpu    = var.processor_cpu_request
            }
            limits = {
              memory = var.processor_memory_limit
              cpu    = var.processor_cpu_limit
            }
          }
          
          port {
            container_port = 8080
            name          = "http"
          }
          
          # Health checks
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
        
        # Cloud SQL Proxy sidecar container
        container {
          name  = "cloud-sql-proxy"
          image = "gcr.io/cloudsql-docker/gce-proxy:1.33.2"
          
          command = [
            "/cloud_sql_proxy",
            "-instances=${var.project_id}:${var.region}:${google_sql_database_instance.inventory_db.name}=tcp:5432"
          ]
          
          security_context {
            run_as_non_root = true
          }
          
          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "200m"
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    kubernetes_service_account.edge_processor_k8s,
    google_container_node_pool.edge_nodes
  ]
}

# Create Kubernetes service for the inventory processor
resource "kubernetes_service" "inventory_processor_service" {
  metadata {
    name      = "inventory-processor"
    namespace = "default"
    
    labels = merge(local.common_labels, {
      app = "inventory-processor"
    })
  }
  
  spec {
    selector = {
      app = "inventory-processor"
    }
    
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
    
    type = "ClusterIP"
  }
}

# Create Vision API product set for inventory items
resource "google_ml_engine_model" "product_set" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${var.resource_prefix}-product-set"
  description = var.product_set_display_name
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring dashboard for inventory intelligence
resource "google_monitoring_dashboard" "inventory_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Inventory Intelligence Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Inventory Levels by Location"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"global\""
                  aggregation = {
                    alignmentPeriod   = "60s"
                    perSeriesAligner  = "ALIGN_MEAN"
                  }
                }
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Processing Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_container\""
                      aggregation = {
                        alignmentPeriod   = "60s"
                        perSeriesAligner  = "ALIGN_RATE"
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

# Create notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Inventory Alerts Email"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy for low inventory
resource "google_monitoring_alert_policy" "low_inventory_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Low Inventory Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Inventory Count Low"
    
    condition_threshold {
      filter         = "resource.type=\"global\""
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = var.inventory_threshold
      duration       = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  documentation {
    content = "Alert triggered when inventory levels fall below the configured threshold of ${var.inventory_threshold} items."
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
  
  depends_on = [google_project_service.required_apis]
}