# Zero-Downtime Database Migration Infrastructure with Cloud SQL and Database Migration Service

# ============================================================================
# LOCAL VALUES AND RESOURCE NAMING
# ============================================================================

locals {
  # Generate consistent resource names with random suffix for uniqueness
  name_prefix = "${var.environment}-db-migration"
  
  # Common labels applied to all resources
  common_labels = merge({
    environment    = var.environment
    project        = "zero-downtime-migration"
    managed_by     = "terraform"
    migration_type = var.migration_type
    created_date   = formatdate("YYYY-MM-DD", timestamp())
  }, var.labels)
  
  # Resource names with auto-generated suffixes
  vpc_name               = var.vpc_name != "" ? var.vpc_name : "${local.name_prefix}-vpc"
  cloudsql_instance_name = var.cloudsql_instance_name != "" ? var.cloudsql_instance_name : "${local.name_prefix}-mysql"
  migration_job_id       = "${local.name_prefix}-job-${random_string.suffix.result}"
  connection_profile_id  = "${local.name_prefix}-source-${random_string.suffix.result}"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ============================================================================

# Enable Database Migration Service API
resource "google_project_service" "datamigration_api" {
  service            = "datamigration.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud SQL Admin API
resource "google_project_service" "sqladmin_api" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Monitoring API
resource "google_project_service" "monitoring_api" {
  count              = var.enable_monitoring ? 1 : 0
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Logging API
resource "google_project_service" "logging_api" {
  count              = var.enable_logging ? 1 : 0
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

# Enable Compute Engine API for networking
resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Enable Service Networking API for private connections
resource "google_project_service" "servicenetworking_api" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# Wait for APIs to be enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [
    google_project_service.datamigration_api,
    google_project_service.sqladmin_api,
    google_project_service.monitoring_api,
    google_project_service.logging_api,
    google_project_service.compute_api,
    google_project_service.servicenetworking_api
  ]
  create_duration = "60s"
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# Create VPC network for secure private connectivity
resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
  routing_mode           = "REGIONAL"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create subnet for Cloud SQL and migration resources
resource "google_compute_subnetwork" "subnet" {
  name          = "${local.name_prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.vpc.id
  region        = var.region
  
  # Enable private Google access for Cloud SQL
  private_ip_google_access = true
  
  # Secondary IP ranges for services if needed
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "192.168.1.0/24"
  }
}

# Allocate IP range for private services (Cloud SQL)
resource "google_compute_global_address" "private_ip_range" {
  name          = "${local.name_prefix}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Create private connection to Google services
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
  
  depends_on = [google_project_service.servicenetworking_api]
}

# ============================================================================
# CLOUD SQL INFRASTRUCTURE
# ============================================================================

# Create Cloud SQL for MySQL instance as migration target
resource "google_sql_database_instance" "target_mysql" {
  name                = local.cloudsql_instance_name
  database_version    = var.database_version
  region              = var.region
  deletion_protection = var.deletion_protection
  
  # Instance configuration
  settings {
    tier                        = var.database_tier
    edition                     = "ENTERPRISE"
    availability_type           = var.availability_type
    disk_autoresize            = true
    disk_autoresize_limit      = var.disk_size * 2
    disk_size                  = var.disk_size
    disk_type                  = "PD_SSD"
    deletion_protection_enabled = var.deletion_protection
    
    # Backup configuration for data protection
    backup_configuration {
      enabled                        = true
      binary_log_enabled            = true
      start_time                    = var.backup_start_time
      location                      = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }
    
    # Network configuration for private connectivity
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
      
      # Add authorized networks if specified
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Maintenance window configuration
    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }
    
    # Performance insights for monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length    = 1024
      record_application_tags = true
      record_client_address  = true
    }
    
    # Apply common labels
    user_labels = local.common_labels
  }
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    time_sleep.wait_for_apis
  ]
}

# Create production database
resource "google_sql_database" "production_db" {
  name     = "production_db"
  instance = google_sql_database_instance.target_mysql.name
}

# Create migration user for database operations
resource "google_sql_user" "migration_user" {
  name     = var.source_database_username
  instance = google_sql_database_instance.target_mysql.name
  password = var.source_database_password != "" ? var.source_database_password : random_string.db_password.result
}

# Create application user for post-migration connectivity
resource "google_sql_user" "app_user" {
  name     = "app_user"
  instance = google_sql_database_instance.target_mysql.name
  password = random_string.app_password.result
}

# Generate secure passwords if not provided
resource "random_string" "db_password" {
  length  = 16
  special = true
}

resource "random_string" "app_password" {
  length  = 16
  special = true
}

# Create read replica for testing and failover
resource "google_sql_database_instance" "read_replica" {
  name                 = "${local.cloudsql_instance_name}-replica"
  master_instance_name = google_sql_database_instance.target_mysql.name
  region               = var.region
  
  replica_configuration {
    failover_target = false
  }
  
  settings {
    tier                = "db-n1-standard-1"
    availability_type   = "ZONAL"
    disk_autoresize    = true
    user_labels        = local.common_labels
  }
}

# ============================================================================
# DATABASE MIGRATION SERVICE CONFIGURATION
# ============================================================================

# Create connection profile for source MySQL database
resource "google_database_migration_service_connection_profile" "source_mysql" {
  provider             = google-beta
  location             = var.region
  connection_profile_id = local.connection_profile_id
  display_name         = "Source MySQL Database Connection"
  
  mysql {
    host     = var.source_database_host
    port     = var.source_database_port
    username = var.source_database_username
    password = var.source_database_password != "" ? var.source_database_password : random_string.db_password.result
    
    ssl {
      type = "SERVER_ONLY"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create migration job for zero-downtime migration
resource "google_database_migration_service_migration_job" "mysql_migration" {
  provider         = google-beta
  location         = var.region
  migration_job_id = local.migration_job_id
  display_name     = "Production MySQL Migration Job"
  type             = var.migration_type
  
  source           = google_database_migration_service_connection_profile.source_mysql.name
  destination      = google_sql_database_instance.target_mysql.connection_name
  
  # Configure VPC peering connectivity
  dynamic "vpc_peering_connectivity" {
    for_each = var.connectivity_type == "vpc_peering" ? [1] : []
    content {
      vpc = google_compute_network.vpc.id
    }
  }
  
  # Configure static IP connectivity
  dynamic "static_ip_connectivity" {
    for_each = var.connectivity_type == "static_ip" ? [1] : []
    content {}
  }
  
  # Configure dump path if specified
  dynamic "dump_path" {
    for_each = var.dump_path != "" ? [var.dump_path] : []
    content {
      gcs_bucket = split("/", var.dump_path)[2]
      gcs_path   = join("/", slice(split("/", var.dump_path), 3, length(split("/", var.dump_path))))
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_sql_database_instance.target_mysql
  ]
}

# ============================================================================
# MONITORING AND ALERTING INFRASTRUCTURE
# ============================================================================

# Create log-based metric for migration errors
resource "google_logging_metric" "migration_errors" {
  count  = var.enable_logging ? 1 : 0
  name   = "${local.name_prefix}-migration-errors"
  filter = "resource.type=\"gce_instance\" AND jsonPayload.message:\"ERROR\" AND jsonPayload.service:\"database-migration\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Database Migration Errors"
  }
  
  label_extractors = {
    "error_type" = "EXTRACT(jsonPayload.error_type)"
  }
}

# Create notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  display_name = "${local.name_prefix} Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}

# Create alert policy for Cloud SQL CPU utilization
resource "google_monitoring_alert_policy" "sql_cpu_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${local.name_prefix} Cloud SQL High CPU"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud SQL CPU Utilization > ${var.alert_cpu_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.target_mysql.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Create alert policy for Cloud SQL memory utilization
resource "google_monitoring_alert_policy" "sql_memory_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${local.name_prefix} Cloud SQL High Memory"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud SQL Memory Utilization > ${var.alert_memory_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.target_mysql.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Create alert policy for migration job failures
resource "google_monitoring_alert_policy" "migration_failure_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${local.name_prefix} Migration Job Failure"
  combiner     = "OR"
  
  conditions {
    display_name = "Database Migration Job Failed"
    
    condition_threshold {
      filter          = "resource.type=\"datamigration.googleapis.com/MigrationJob\" AND resource.label.migration_job_id=\"${local.migration_job_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "3600s"
  }
}

# ============================================================================
# MONITORING DASHBOARD
# ============================================================================

# Create comprehensive monitoring dashboard
resource "google_monitoring_dashboard" "migration_dashboard" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "${local.name_prefix} Database Migration Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud SQL CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.target_mysql.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 0
          xPos   = 6
          widget = {
            title = "Cloud SQL Memory Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.target_mysql.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Migration Job Status"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"datamigration.googleapis.com/MigrationJob\""
                    aggregation = {
                      alignmentPeriod  = "300s"
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
}