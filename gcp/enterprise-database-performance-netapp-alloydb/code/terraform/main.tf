# Enterprise Database Performance Solution with NetApp Volumes and AlloyDB
# This Terraform configuration deploys a high-performance database architecture
# combining Google Cloud NetApp Volumes with AlloyDB for PostgreSQL

# Local values for resource naming and configuration
locals {
  # Generate random suffix for unique resource names
  random_suffix = random_id.resource_suffix.hex
  
  # Resource naming with consistent pattern
  alloydb_cluster_id       = var.alloydb_cluster_id != "" ? var.alloydb_cluster_id : "enterprise-alloydb-${local.random_suffix}"
  netapp_storage_pool_name = var.netapp_storage_pool_name != "" ? var.netapp_storage_pool_name : "enterprise-storage-pool-${local.random_suffix}"
  netapp_volume_name       = var.netapp_volume_name != "" ? var.netapp_volume_name : "enterprise-db-volume-${local.random_suffix}"
  
  # Common labels for all resources
  common_labels = {
    environment   = var.environment
    owner        = var.owner
    project      = var.project_name
    cost_center  = var.cost_center
    managed_by   = "terraform"
    solution     = "enterprise-database-performance"
  }
  
  # Database flags for performance optimization
  database_flags = {
    shared_preload_libraries = "pg_stat_statements,pg_hint_plan"
    work_mem                = "256MB"
    effective_cache_size    = "${var.primary_memory_size_gb * 0.75}GB"
    max_connections         = "500"
    checkpoint_timeout      = "15min"
    checkpoint_completion_target = "0.9"
  }
}

# Random ID for unique resource naming
resource "random_id" "resource_suffix" {
  byte_length = 3
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# VPC Network for enterprise database infrastructure
resource "google_compute_network" "enterprise_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  description            = "Enterprise database VPC network for high-performance workloads"
  
  # Enable global routing for cross-region connectivity
  routing_mode = "GLOBAL"
  
  # Wait for API enablement
  depends_on = [time_sleep.api_enablement]
}

# Subnet for database resources with appropriate CIDR
resource "google_compute_subnetwork" "database_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.enterprise_vpc.id
  description   = "Database subnet for AlloyDB and application connectivity"
  
  # Enable private Google access for API connectivity
  private_ip_google_access = true
  
  # Secondary ranges for GKE pods and services (if needed)
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.2.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.3.0.0/16"
  }
}

# Global IP address allocation for private service connection
resource "google_compute_global_address" "private_service_range" {
  name          = "alloydb-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.enterprise_vpc.id
  description   = "Private IP range for AlloyDB service networking"
}

# Private service connection for AlloyDB
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.enterprise_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
  
  # Ensure proper dependency order
  depends_on = [google_compute_global_address.private_service_range]
}

# Firewall rule for AlloyDB connectivity
resource "google_compute_firewall" "alloydb_firewall" {
  name    = "allow-alloydb-${local.random_suffix}"
  network = google_compute_network.enterprise_vpc.name
  
  description = "Allow PostgreSQL connectivity to AlloyDB instances"
  
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
  
  source_ranges = [var.subnet_cidr]
  target_tags   = ["alloydb"]
  
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule for NetApp Volumes NFS connectivity
resource "google_compute_firewall" "netapp_nfs_firewall" {
  name    = "allow-netapp-nfs-${local.random_suffix}"
  network = google_compute_network.enterprise_vpc.name
  
  description = "Allow NFS connectivity to NetApp Volumes"
  
  allow {
    protocol = "tcp"
    ports    = ["111", "2049", "4045", "4046"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["111", "2049", "4045", "4046"]
  }
  
  source_ranges = [var.subnet_cidr]
  target_tags   = ["netapp-volumes"]
}

# ============================================================================
# SECURITY AND ENCRYPTION
# ============================================================================

# KMS Keyring for database encryption
resource "google_kms_key_ring" "alloydb_keyring" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name     = var.kms_keyring_name
  location = var.region
  
  lifecycle {
    prevent_destroy = true
  }
}

# KMS Key for AlloyDB encryption
resource "google_kms_crypto_key" "alloydb_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name     = var.kms_key_name
  key_ring = google_kms_key_ring.alloydb_keyring[0].id
  purpose  = "ENCRYPT_DECRYPT"
  
  # Automatic key rotation every 90 days
  rotation_period = "7776000s"  # 90 days
  
  lifecycle {
    prevent_destroy = true
  }
  
  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}

# IAM binding for AlloyDB service to use KMS key
resource "google_kms_crypto_key_iam_binding" "alloydb_key_binding" {
  count = var.enable_kms_encryption ? 1 : 0
  
  crypto_key_id = google_kms_crypto_key.alloydb_key[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  
  members = [
    "serviceAccount:service-${data.google_project.current.number}@gcp-sa-alloydb.iam.gserviceaccount.com"
  ]
}

# ============================================================================
# NETAPP VOLUMES STORAGE
# ============================================================================

# NetApp Volumes Storage Pool with custom performance configuration
resource "google_netapp_storage_pool" "enterprise_storage_pool" {
  name          = local.netapp_storage_pool_name
  location      = var.region
  service_level = var.netapp_storage_service_level
  capacity_gib  = var.netapp_storage_pool_capacity_tib * 1024  # Convert TiB to GiB
  network       = google_compute_network.enterprise_vpc.id
  
  description = "Enterprise-grade storage pool for high-performance database workloads"
  
  labels = local.common_labels
  
  # Ensure network is ready before creating storage pool
  depends_on = [google_compute_network.enterprise_vpc]
}

# NetApp Volume for database data storage
resource "google_netapp_volume" "database_volume" {
  name         = local.netapp_volume_name
  location     = var.region
  capacity_gib = var.netapp_volume_capacity_gib
  share_name   = var.netapp_volume_share_name
  storage_pool = google_netapp_storage_pool.enterprise_storage_pool.name
  protocols    = var.netapp_protocols
  
  description = "High-performance volume for enterprise database data storage"
  
  # Export policy for NFS access
  export_policy {
    rules {
      allowed_clients = var.subnet_cidr
      access_type     = "READ_WRITE"
      nfsv3          = contains(var.netapp_protocols, "NFSV3")
      nfsv4          = contains(var.netapp_protocols, "NFSV4")
      has_root_access = true
    }
  }
  
  # Snapshot policy for data protection
  snapshot_policy {
    enabled = true
    
    daily_schedule {
      snapshots_to_keep = 7
      hour             = 2
      minute           = 0
    }
    
    weekly_schedule {
      snapshots_to_keep = 4
      day              = "SUNDAY"
      hour             = 3
      minute           = 0
    }
    
    monthly_schedule {
      snapshots_to_keep = 12
      days_of_month     = "1"
      hour              = 4
      minute            = 0
    }
  }
  
  labels = local.common_labels
  
  # Wait for storage pool to be ready
  depends_on = [google_netapp_storage_pool.enterprise_storage_pool]
}

# ============================================================================
# ALLOYDB CLUSTER AND INSTANCES
# ============================================================================

# AlloyDB Cluster for enterprise PostgreSQL workloads
resource "google_alloydb_cluster" "enterprise_cluster" {
  cluster_id   = local.alloydb_cluster_id
  location     = var.region
  network      = google_compute_network.enterprise_vpc.id
  
  # Database configuration
  database_version = var.alloydb_database_version
  
  # Initial user configuration
  initial_user {
    user     = "postgres"
    password = var.alloydb_password
  }
  
  # Automated backup configuration
  automated_backup_policy {
    location      = var.region
    backup_window = "23400s"  # 6.5 hours starting from backup_start_time
    enabled       = true
    
    weekly_schedule {
      days_of_week = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
      start_times {
        hours   = tonumber(split(":", var.backup_start_time)[0])
        minutes = tonumber(split(":", var.backup_start_time)[1])
      }
    }
    
    quantity_based_retention {
      count = var.backup_retention_days
    }
    
    labels = local.common_labels
  }
  
  # Continuous backup configuration
  continuous_backup_config {
    enabled              = true
    recovery_window_days = 14
  }
  
  # Customer-managed encryption
  dynamic "encryption_config" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      kms_key_name = google_kms_crypto_key.alloydb_key[0].id
    }
  }
  
  labels = local.common_labels
  
  # Dependencies
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_kms_crypto_key_iam_binding.alloydb_key_binding
  ]
}

# Primary AlloyDB Instance for transactional workloads
resource "google_alloydb_instance" "primary_instance" {
  cluster       = google_alloydb_cluster.enterprise_cluster.name
  instance_id   = "${local.alloydb_cluster_id}-primary"
  instance_type = "PRIMARY"
  
  # Machine configuration for high performance
  machine_config {
    cpu_count = var.primary_cpu_count
  }
  
  # Database flags for performance optimization
  database_flags = local.database_flags
  
  # Query insights configuration
  query_insights_config {
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 20
  }
  
  # Read pool configuration for analytics
  read_pool_config {
    node_count = 0  # Will be configured on read replicas
  }
  
  labels = merge(local.common_labels, {
    instance_type = "primary"
    workload_type = "transactional"
  })
  
  depends_on = [google_alloydb_cluster.enterprise_cluster]
}

# Read Replica Instance for analytical workloads
resource "google_alloydb_instance" "read_replica" {
  count = var.enable_read_replicas ? 1 : 0
  
  cluster       = google_alloydb_cluster.enterprise_cluster.name
  instance_id   = "${local.alloydb_cluster_id}-replica-01"
  instance_type = "READ_POOL"
  
  # Machine configuration optimized for read workloads
  machine_config {
    cpu_count = var.replica_cpu_count
  }
  
  # Read pool configuration for horizontal scaling
  read_pool_config {
    node_count = var.read_pool_node_count
  }
  
  # Query insights for read workloads
  query_insights_config {
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 10
  }
  
  labels = merge(local.common_labels, {
    instance_type = "read_replica"
    workload_type = "analytical"
  })
  
  depends_on = [google_alloydb_instance.primary_instance]
}

# ============================================================================
# LOAD BALANCING AND CONNECTIVITY
# ============================================================================

# Health check for AlloyDB connectivity
resource "google_compute_health_check" "alloydb_health_check" {
  count = var.enable_load_balancer ? 1 : 0
  
  name               = "alloydb-health-check-${local.random_suffix}"
  check_interval_sec = 10
  timeout_sec        = 5
  
  tcp_health_check {
    port = "5432"
  }
  
  log_config {
    enable = true
  }
}

# Backend service for AlloyDB load balancing
resource "google_compute_region_backend_service" "alloydb_backend" {
  count = var.enable_load_balancer ? 1 : 0
  
  name                  = "alloydb-backend-${local.random_suffix}"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  
  health_checks = [google_compute_health_check.alloydb_health_check[0].id]
  
  # Connection draining timeout
  timeout_sec = 30
  
  # Session affinity for connection consistency
  session_affinity = "CLIENT_IP"
}

# Internal load balancer forwarding rule
resource "google_compute_forwarding_rule" "alloydb_forwarding_rule" {
  count = var.enable_load_balancer ? 1 : 0
  
  name                  = "alloydb-forwarding-rule-${local.random_suffix}"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.alloydb_backend[0].id
  
  # Network configuration
  network    = google_compute_network.enterprise_vpc.id
  subnetwork = google_compute_subnetwork.database_subnet.id
  
  # Static IP for consistent connectivity
  ip_address = var.load_balancer_ip
  ports      = ["5432"]
  
  # Service label for identification
  service_label = "alloydb"
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Cloud Monitoring Dashboard for database performance
resource "google_monitoring_dashboard" "database_performance_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Enterprise Database Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "AlloyDB CPU Utilization"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"alloydb_instance\" AND resource.labels.cluster_id=\"${local.alloydb_cluster_id}\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
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
            title = "AlloyDB Memory Utilization"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"alloydb_instance\" AND resource.labels.cluster_id=\"${local.alloydb_cluster_id}\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
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
            title = "NetApp Volume Performance"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"netapp_volume\" AND resource.labels.volume_id=\"${local.netapp_volume_name}\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
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
            title = "Database Connections"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"alloydb_instance\" AND metric.type=\"alloydb.googleapis.com/database/connection/count\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }
          }
        }
      ]
    }
  })
}

# Alert policy for AlloyDB high CPU utilization
resource "google_monitoring_alert_policy" "alloydb_high_cpu" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AlloyDB High CPU Alert - ${local.alloydb_cluster_id}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "AlloyDB CPU > ${var.alert_cpu_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"alloydb_instance\" AND resource.labels.cluster_id=\"${local.alloydb_cluster_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  documentation {
    content = "AlloyDB instance CPU utilization is above ${var.alert_cpu_threshold * 100}%. Consider scaling up the instance or optimizing queries."
  }
}

# Alert policy for AlloyDB high memory utilization
resource "google_monitoring_alert_policy" "alloydb_high_memory" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AlloyDB High Memory Alert - ${local.alloydb_cluster_id}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "AlloyDB Memory > ${var.alert_memory_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"alloydb_instance\" AND resource.labels.cluster_id=\"${local.alloydb_cluster_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  documentation {
    content = "AlloyDB instance memory utilization is above ${var.alert_memory_threshold * 100}%. Consider scaling up the instance or optimizing memory usage."
  }
}

# ============================================================================
# DATA SOURCES AND DEPENDENCIES
# ============================================================================

# Current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Wait for API enablement
resource "time_sleep" "api_enablement" {
  create_duration = "30s"
  
  triggers = {
    project_id = var.project_id
  }
}