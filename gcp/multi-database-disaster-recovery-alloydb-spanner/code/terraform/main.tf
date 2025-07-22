# ==============================================================================
# Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner
# ==============================================================================
# This Terraform configuration deploys a comprehensive disaster recovery
# solution combining AlloyDB for PostgreSQL workloads and Cloud Spanner for
# globally distributed data, with automated backup orchestration and
# cross-region failover capabilities.
# ==============================================================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# ==============================================================================
# NETWORKING INFRASTRUCTURE
# ==============================================================================

# VPC Network for AlloyDB connectivity
resource "google_compute_network" "alloydb_network" {
  name                    = "alloydb-dr-network-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "VPC network for AlloyDB disaster recovery setup"

  depends_on = [
    google_project_service.compute
  ]
}

# Primary region subnet for AlloyDB
resource "google_compute_subnetwork" "primary_subnet" {
  name          = "alloydb-primary-subnet-${random_id.suffix.hex}"
  ip_cidr_range = var.primary_subnet_cidr
  region        = var.primary_region
  network       = google_compute_network.alloydb_network.id
  description   = "Primary region subnet for AlloyDB"

  secondary_ip_range {
    range_name    = "alloydb-secondary-range"
    ip_cidr_range = var.primary_secondary_cidr
  }
}

# Secondary region subnet for disaster recovery
resource "google_compute_subnetwork" "secondary_subnet" {
  name          = "alloydb-secondary-subnet-${random_id.suffix.hex}"
  ip_cidr_range = var.secondary_subnet_cidr
  region        = var.secondary_region
  network       = google_compute_network.alloydb_network.id
  description   = "Secondary region subnet for AlloyDB disaster recovery"

  secondary_ip_range {
    range_name    = "alloydb-secondary-range-dr"
    ip_cidr_range = var.secondary_secondary_cidr
  }
}

# Service networking connection for AlloyDB
resource "google_service_networking_connection" "alloydb_connection" {
  network                 = google_compute_network.alloydb_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.alloydb_ip_range.name]

  depends_on = [
    google_project_service.servicenetworking
  ]
}

# Reserved IP range for AlloyDB
resource "google_compute_global_address" "alloydb_ip_range" {
  name          = "alloydb-ip-range-${random_id.suffix.hex}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.alloydb_network.id
  description   = "IP range reserved for AlloyDB instances"
}

# ==============================================================================
# CROSS-REGION BACKUP STORAGE
# ==============================================================================

# Primary region backup bucket
resource "google_storage_bucket" "primary_backup" {
  name          = "${var.backup_bucket_prefix}-primary-${random_id.suffix.hex}"
  location      = var.primary_region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

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

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    region      = "primary"
  }

  depends_on = [
    google_project_service.storage
  ]
}

# Secondary region backup bucket for cross-region protection
resource "google_storage_bucket" "secondary_backup" {
  name          = "${var.backup_bucket_prefix}-secondary-${random_id.suffix.hex}"
  location      = var.secondary_region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

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

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    region      = "secondary"
  }

  depends_on = [
    google_project_service.storage
  ]
}

# Bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.backup_bucket_prefix}-functions-${random_id.suffix.hex}"
  location      = var.primary_region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    environment = var.environment
    purpose     = "cloud-functions"
  }

  depends_on = [
    google_project_service.storage
  ]
}

# ==============================================================================
# ALLOYDB DISASTER RECOVERY SETUP
# ==============================================================================

# AlloyDB Primary Cluster
resource "google_alloydb_cluster" "primary" {
  cluster_id   = "${var.cluster_name}-primary-${random_id.suffix.hex}"
  location     = var.primary_region
  network_config {
    network = google_compute_network.alloydb_network.id
  }

  database_version = "POSTGRES_15"

  initial_user {
    user     = var.db_admin_user
    password = var.db_admin_password
  }

  # Automated backup configuration
  automated_backup_policy {
    location      = var.primary_region
    backup_window = "14400s" # 4 hours
    enabled       = true

    weekly_schedule {
      days_of_week = ["MONDAY", "WEDNESDAY", "FRIDAY"]
      start_times {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }

    quantity_based_retention {
      count = 14 # Keep 14 backups
    }

    time_based_retention {
      retention_period = "336h" # 14 days
    }
  }

  # Continuous backup with point-in-time recovery
  continuous_backup_config {
    enabled              = true
    recovery_window_days = 14
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    role        = "primary"
  }

  depends_on = [
    google_service_networking_connection.alloydb_connection,
    google_project_service.alloydb
  ]
}

# AlloyDB Primary Instance
resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.primary.name
  instance_id   = "primary-instance"
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.alloydb_cpu_count
  }

  availability_type = "REGIONAL"

  # Enable query insights for monitoring
  query_insights_config {
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 5
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    role        = "primary"
  }

  depends_on = [
    google_alloydb_cluster.primary
  ]
}

# AlloyDB Secondary Cluster for cross-region disaster recovery
resource "google_alloydb_cluster" "secondary" {
  cluster_id   = "${var.cluster_name}-secondary-${random_id.suffix.hex}"
  location     = var.secondary_region
  cluster_type = "SECONDARY"

  network_config {
    network = google_compute_network.alloydb_network.id
  }

  # Secondary clusters don't support continuous backup
  continuous_backup_config {
    enabled = false
  }

  secondary_config {
    primary_cluster_name = google_alloydb_cluster.primary.name
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    role        = "secondary"
  }

  depends_on = [
    google_alloydb_cluster.primary,
    google_service_networking_connection.alloydb_connection
  ]
}

# AlloyDB Read Pool Instance in secondary cluster
resource "google_alloydb_instance" "secondary_read_pool" {
  cluster       = google_alloydb_cluster.secondary.name
  instance_id   = "secondary-read-pool"
  instance_type = "READ_POOL"

  machine_config {
    cpu_count = var.alloydb_read_pool_cpu_count
  }

  read_pool_config {
    node_count = var.alloydb_read_pool_nodes
  }

  availability_type = "REGIONAL"

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    role        = "read-pool"
  }

  depends_on = [
    google_alloydb_cluster.secondary
  ]
}

# ==============================================================================
# CLOUD SPANNER MULTI-REGION SETUP
# ==============================================================================

# Cloud Spanner Multi-Region Instance
resource "google_spanner_instance" "multi_regional" {
  config       = var.spanner_config
  display_name = "Disaster Recovery Spanner Instance"
  
  # Use processing_units for better autoscaling support
  processing_units = var.spanner_processing_units

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
    type        = "multi-regional"
  }

  depends_on = [
    google_project_service.spanner
  ]
}

# Cloud Spanner Database with critical data schema
resource "google_spanner_database" "critical_data" {
  instance = google_spanner_instance.multi_regional.name
  name     = "critical-data"

  ddl = [
    # User profiles table for critical user data
    "CREATE TABLE UserProfiles (UserId STRING(64) NOT NULL, UserName STRING(100), Email STRING(255), CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true), LastModified TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true), Region STRING(50), Status STRING(20)) PRIMARY KEY (UserId)",
    
    # Transaction log table interleaved with user profiles
    "CREATE TABLE TransactionLog (TransactionId STRING(64) NOT NULL, UserId STRING(64) NOT NULL, Amount NUMERIC, Currency STRING(3), Timestamp TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true), Status STRING(20), Source STRING(50)) PRIMARY KEY (TransactionId), INTERLEAVE IN PARENT UserProfiles ON DELETE CASCADE",
    
    # Configuration table for application settings
    "CREATE TABLE SystemConfig (ConfigKey STRING(100) NOT NULL, ConfigValue STRING(MAX), Environment STRING(20), LastUpdated TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)) PRIMARY KEY (ConfigKey)",
    
    # Audit log table for compliance
    "CREATE TABLE AuditLog (LogId STRING(64) NOT NULL, UserId STRING(64), Action STRING(100), Resource STRING(200), Timestamp TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true), IpAddress STRING(45), UserAgent STRING(500)) PRIMARY KEY (LogId)"
  ]

  deletion_protection = true

  depends_on = [
    google_spanner_instance.multi_regional
  ]
}

# ==============================================================================
# SERVICE ACCOUNTS AND IAM
# ==============================================================================

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "dr-function-sa-${random_id.suffix.hex}"
  display_name = "Disaster Recovery Function Service Account"
  description  = "Service account for disaster recovery Cloud Functions"
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "dr-scheduler-sa-${random_id.suffix.hex}"
  display_name = "Disaster Recovery Scheduler Service Account"
  description  = "Service account for disaster recovery Cloud Scheduler jobs"
}

# Service account for Pub/Sub
resource "google_service_account" "pubsub_sa" {
  account_id   = "dr-pubsub-sa-${random_id.suffix.hex}"
  display_name = "Disaster Recovery Pub/Sub Service Account"
  description  = "Service account for disaster recovery Pub/Sub operations"
}

# IAM bindings for function service account - AlloyDB permissions
resource "google_project_iam_member" "function_alloydb_admin" {
  project = var.project_id
  role    = "roles/alloydb.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for function service account - Spanner permissions
resource "google_project_iam_member" "function_spanner_admin" {
  project = var.project_id
  role    = "roles/spanner.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for function service account - Storage permissions
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for function service account - Monitoring permissions
resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for scheduler service account
resource "google_project_iam_member" "scheduler_cloudfunctions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# IAM bindings for Pub/Sub service account
resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.pubsub_sa.email}"
}

# ==============================================================================
# PUB/SUB MESSAGING FOR DATA SYNCHRONIZATION
# ==============================================================================

# Pub/Sub topic for database synchronization events
resource "google_pubsub_topic" "database_sync_events" {
  name = "database-sync-events-${random_id.suffix.hex}"

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
  }

  message_retention_duration = "604800s" # 7 days

  message_storage_policy {
    allowed_persistence_regions = [
      var.primary_region,
      var.secondary_region
    ]
    enforce_in_transit = true
  }

  depends_on = [
    google_project_service.pubsub
  ]
}

# Pub/Sub subscription for monitoring sync operations
resource "google_pubsub_subscription" "database_sync_monitoring" {
  name  = "database-sync-monitoring-${random_id.suffix.hex}"
  topic = google_pubsub_topic.database_sync_events.id

  ack_deadline_seconds       = 60
  message_retention_duration = "1200s"
  retain_acked_messages      = false

  expiration_policy {
    ttl = "86400s" # 1 day
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
  }

  depends_on = [
    google_pubsub_topic.database_sync_events
  ]
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "database-sync-dead-letter-${random_id.suffix.hex}"

  labels = {
    environment = var.environment
    purpose     = "disaster-recovery"
  }

  message_retention_duration = "2592000s" # 30 days

  depends_on = [
    google_project_service.pubsub
  ]
}

# ==============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIs
# ==============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "alloydb" {
  service            = "alloydb.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "spanner" {
  service            = "spanner.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}