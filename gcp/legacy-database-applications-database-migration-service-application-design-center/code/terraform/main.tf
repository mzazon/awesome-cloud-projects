# ===================================================
# Legacy Database Applications Migration Solution
# Using Database Migration Service & Application Design Center
# ===================================================

# Local values for resource naming and configuration
locals {
  base_name = var.base_name
  region    = var.region
  zone      = var.zone
  
  # Generate common labels
  common_labels = {
    environment = var.environment
    project     = "legacy-db-migration"
    managed-by  = "terraform"
    recipe      = "legacy-database-applications-database-migration-service-application-design-center"
  }
  
  # Network configuration
  network_name = "${local.base_name}-vpc"
  subnet_name  = "${local.base_name}-subnet"
  
  # Cloud SQL configuration
  postgres_instance_name = "${local.base_name}-postgres"
  postgres_user          = "migration_user"
  
  # Database Migration Service configuration
  source_connection_profile_id = "${local.base_name}-source-profile"
  dest_connection_profile_id   = "${local.base_name}-dest-profile"
  migration_job_id             = "${local.base_name}-migration-job"
}

# ===================================================
# Data Sources
# ===================================================

# Get current project information
data "google_project" "current" {}

# Get available zones in the region
data "google_compute_zones" "available" {
  region = local.region
}

# ===================================================
# Random Resources for Unique Naming
# ===================================================

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Generate secure password for database users
resource "random_password" "postgres_password" {
  length  = 16
  special = true
}

# Generate secure password for SQL Server source (for example purposes)
resource "random_password" "sqlserver_password" {
  length  = 16
  special = true
}

# ===================================================
# Network Infrastructure
# ===================================================

# VPC Network for the migration environment
resource "google_compute_network" "migration_network" {
  name                    = "${local.network_name}-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  description            = "VPC network for legacy database migration project"
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Subnet for the migration resources
resource "google_compute_subnetwork" "migration_subnet" {
  name          = "${local.subnet_name}-${random_id.suffix.hex}"
  network       = google_compute_network.migration_network.id
  ip_cidr_range = var.subnet_cidr
  region        = local.region
  description   = "Subnet for legacy database migration resources"
  
  # Enable private Google access for Cloud SQL
  private_ip_google_access = true
  
  # Secondary ranges for services if needed
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# Global address for private services access
resource "google_compute_global_address" "private_services_access" {
  name          = "${local.base_name}-private-services-${random_id.suffix.hex}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.migration_network.id
  description   = "Global address for private services access"
}

# Private VPC connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.migration_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_access.name]
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_global_address.private_services_access
  ]
}

# ===================================================
# Firewall Rules
# ===================================================

# Allow internal communication within the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.base_name}-allow-internal-${random_id.suffix.hex}"
  network = google_compute_network.migration_network.name
  
  description = "Allow internal communication within migration VPC"
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.subnet_cidr, var.services_cidr]
  target_tags   = ["migration-internal"]
}

# Allow SSH access for management
resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.base_name}-allow-ssh-${random_id.suffix.hex}"
  network = google_compute_network.migration_network.name
  
  description = "Allow SSH access for migration environment management"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.allowed_ssh_sources
  target_tags   = ["migration-ssh"]
}

# Allow Database Migration Service access
resource "google_compute_firewall" "allow_dms" {
  name    = "${local.base_name}-allow-dms-${random_id.suffix.hex}"
  network = google_compute_network.migration_network.name
  
  description = "Allow Database Migration Service access"
  
  allow {
    protocol = "tcp"
    ports    = ["5432", "1433", "3306"] # PostgreSQL, SQL Server, MySQL
  }
  
  source_ranges = ["10.0.0.0/8"] # Private IP ranges
  target_tags   = ["migration-database"]
}

# ===================================================
# Cloud SQL PostgreSQL Instance (Target Database)
# ===================================================

# Cloud SQL PostgreSQL instance for migration target
resource "google_sql_database_instance" "postgres_target" {
  name             = "${local.postgres_instance_name}-${random_id.suffix.hex}"
  database_version = var.postgres_version
  region           = local.region
  
  settings {
    tier                        = var.postgres_tier
    availability_type          = var.postgres_availability_type
    disk_type                  = "PD_SSD"
    disk_size                  = var.postgres_disk_size
    disk_autoresize           = true
    disk_autoresize_limit     = var.postgres_disk_autoresize_limit
    
    # Enable deletion protection for production
    deletion_protection_enabled = var.enable_deletion_protection
    
    # Backup configuration for data protection
    backup_configuration {
      enabled                        = true
      start_time                    = "03:00"
      location                      = local.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }
    
    # Network configuration for private access
    ip_configuration {
      ipv4_enabled                                  = var.enable_public_ip
      private_network                               = google_compute_network.migration_network.id
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = true
      
      # Authorized networks for public access (if enabled)
      dynamic "authorized_networks" {
        for_each = var.enable_public_ip ? var.authorized_networks : []
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
    }
    
    # Maintenance window configuration
    maintenance_window {
      day          = 7  # Sunday
      hour         = 4  # 4 AM
      update_track = "stable"
    }
    
    # Database flags for PostgreSQL optimization
    dynamic "database_flags" {
      for_each = var.postgres_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
    
    # Insights configuration for query performance
    insights_config {
      query_insights_enabled  = true
      query_string_length    = 1024
      record_application_tags = true
      record_client_address  = true
    }
    
    # User labels for resource organization
    user_labels = merge(
      local.common_labels,
      {
        role = "migration-target"
        type = "postgresql"
      }
    )
  }
  
  # Deletion protection
  deletion_protection = var.enable_deletion_protection
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.required_apis
  ]
  
  lifecycle {
    prevent_destroy = false # Set to true for production
  }
}

# PostgreSQL user for migration
resource "google_sql_user" "migration_user" {
  name     = local.postgres_user
  instance = google_sql_database_instance.postgres_target.name
  password = random_password.postgres_password.result
  
  depends_on = [google_sql_database_instance.postgres_target]
}

# SSL certificate for secure connections
resource "google_sql_ssl_cert" "postgres_client_cert" {
  common_name = "${local.base_name}-client-cert-${random_id.suffix.hex}"
  instance    = google_sql_database_instance.postgres_target.name
  
  depends_on = [google_sql_database_instance.postgres_target]
}

# ===================================================
# Database Migration Service - Connection Profiles
# ===================================================

# Source connection profile (example for external SQL Server)
# Note: This is a template - real values need to be provided
resource "google_database_migration_service_connection_profile" "source_sqlserver" {
  location              = local.region
  connection_profile_id = "${local.source_connection_profile_id}-${random_id.suffix.hex}"
  display_name          = "SQL Server Source - ${local.base_name}"
  
  labels = merge(
    local.common_labels,
    {
      role = "source"
      type = "sqlserver"
    }
  )
  
  # SQL Server configuration - Replace with actual values
  mysql {  # Using mysql block as example - adjust for actual source type
    host     = var.source_database_host
    port     = var.source_database_port
    username = var.source_database_username
    password = var.source_database_password
    
    # SSL configuration if required
    ssl {
      type = var.source_ssl_type
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Destination connection profile for Cloud SQL PostgreSQL
resource "google_database_migration_service_connection_profile" "dest_postgres" {
  location              = local.region
  connection_profile_id = "${local.dest_connection_profile_id}-${random_id.suffix.hex}"
  display_name          = "PostgreSQL Destination - ${local.base_name}"
  
  labels = merge(
    local.common_labels,
    {
      role = "destination" 
      type = "postgresql"
    }
  )
  
  # PostgreSQL configuration pointing to Cloud SQL instance
  postgresql {
    cloud_sql_id = google_sql_database_instance.postgres_target.name
    host         = google_sql_database_instance.postgres_target.private_ip_address
    port         = 5432
    username     = google_sql_user.migration_user.name
    password     = google_sql_user.migration_user.password
    
    # SSL configuration for secure connection
    ssl {
      client_key         = google_sql_ssl_cert.postgres_client_cert.private_key
      client_certificate = google_sql_ssl_cert.postgres_client_cert.cert
      ca_certificate     = google_sql_ssl_cert.postgres_client_cert.server_ca_cert
      type              = "SERVER_CLIENT"
    }
  }
  
  depends_on = [
    google_sql_database_instance.postgres_target,
    google_sql_user.migration_user,
    google_sql_ssl_cert.postgres_client_cert
  ]
}

# ===================================================
# Database Migration Service - Migration Job
# ===================================================

# Migration job for SQL Server to PostgreSQL
resource "google_database_migration_service_migration_job" "legacy_modernization" {
  location         = local.region
  migration_job_id = "${local.migration_job_id}-${random_id.suffix.hex}"
  display_name     = "Legacy Database Modernization - ${local.base_name}"
  
  labels = merge(
    local.common_labels,
    {
      migration-type = "sqlserver-to-postgresql"
      phase         = "modernization"
    }
  )
  
  # Migration configuration
  type        = var.migration_type
  source      = google_database_migration_service_connection_profile.source_sqlserver.name
  destination = google_database_migration_service_connection_profile.dest_postgres.name
  
  # VPC peering connectivity for secure communication
  vpc_peering_connectivity {
    vpc = google_compute_network.migration_network.id
  }
  
  # Performance configuration for optimal migration speed
  performance_config {
    dump_parallel_level = var.migration_parallel_level
  }
  
  depends_on = [
    google_database_migration_service_connection_profile.source_sqlserver,
    google_database_migration_service_connection_profile.dest_postgres,
    google_service_networking_connection.private_vpc_connection
  ]
}

# ===================================================
# Application Design Center Resources
# ===================================================

# Note: Application Design Center and Gemini Code Assist resources
# are not available as Terraform resources yet. These would be configured
# through the Google Cloud Console or gcloud CLI commands.
# The following comments show the intended configuration:

# Application Design Center Workspace (configured via CLI)
# - Workspace for legacy application modernization
# - Project for architectural analysis
# - Integration with Gemini Code Assist for code generation

# Source Repository for code modernization tracking
resource "google_sourcerepo_repository" "modernization_repo" {
  name = "${local.base_name}-app-modernization-${random_id.suffix.hex}"
  
  depends_on = [google_project_service.required_apis]
}

# ===================================================
# Monitoring and Observability
# ===================================================

# Cloud Monitoring workspace (automatically created with first metric)
# Custom metrics for migration monitoring
resource "google_monitoring_alert_policy" "migration_failure" {
  display_name = "Database Migration Failure - ${local.base_name}"
  
  conditions {
    display_name = "Migration job failed"
    
    condition_threshold {
      filter         = "resource.type=\"database_migration_service_migration_job\""
      comparison     = "COMPARISON_EQUAL"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels would be configured separately
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for migration activities
resource "google_logging_project_sink" "migration_logs" {
  name = "${local.base_name}-migration-logs-${random_id.suffix.hex}"
  
  # Send migration logs to Cloud Storage for analysis
  destination = "storage.googleapis.com/${google_storage_bucket.migration_logs.name}"
  
  # Filter for Database Migration Service logs
  filter = "resource.type=\"database_migration_service_migration_job\" OR resource.type=\"cloudsql_database\""
  
  # Create unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_storage_bucket.migration_logs]
}

# Cloud Storage bucket for migration logs and artifacts
resource "google_storage_bucket" "migration_logs" {
  name     = "${local.base_name}-migration-logs-${random_id.suffix.hex}"
  location = local.region
  
  labels = merge(
    local.common_labels,
    {
      purpose = "migration-logs"
    }
  )
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 90 # Days
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for log retention
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for log sink writer
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.migration_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.migration_logs.writer_identity
}

# ===================================================
# Required Google Cloud APIs
# ===================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",               # Cloud SQL Admin API
    "datamigration.googleapis.com",          # Database Migration Service API
    "compute.googleapis.com",                # Compute Engine API
    "servicenetworking.googleapis.com",      # Service Networking API
    "sourcerepo.googleapis.com",             # Source Repositories API
    "monitoring.googleapis.com",             # Cloud Monitoring API
    "logging.googleapis.com",                # Cloud Logging API
    "storage.googleapis.com",                # Cloud Storage API
    "cloudaicompanion.googleapis.com",       # Gemini Code Assist API
    "applicationdesigncenter.googleapis.com" # Application Design Center API (if available)
  ])
  
  service = each.value
  
  # Don't disable APIs on destroy to prevent issues
  disable_on_destroy = false
}