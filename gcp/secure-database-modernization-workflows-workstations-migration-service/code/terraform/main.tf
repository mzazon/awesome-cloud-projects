# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for existing resources
data "google_project" "project" {
  project_id = var.project_id
}

data "google_compute_network" "network" {
  name = var.network_name
}

data "google_compute_subnetwork" "subnet" {
  name   = var.subnet_name
  region = var.region
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "workstations.googleapis.com",
    "datamigration.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  # Don't disable services on destroy to avoid breaking other resources
  disable_on_destroy = false
}

# Create Artifact Registry repository for custom container images
resource "google_artifact_registry_repository" "db_migration_images" {
  provider = google-beta
  
  location      = var.region
  repository_id = var.artifact_registry_repo_name
  description   = "Container images for database migration workstations"
  format        = "DOCKER"

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create Secret Manager secret for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "db-credentials-${random_id.suffix.hex}"
  
  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Store database credentials in Secret Manager
resource "google_secret_manager_secret_version" "db_credentials_version" {
  secret = google_secret_manager_secret.db_credentials.name
  
  secret_data = jsonencode({
    host     = var.source_database_host
    port     = var.source_database_port
    username = var.source_database_user
    password = var.source_database_password
    database = var.source_database_name
  })
}

# Create Cloud SQL instance for target database
resource "google_sql_database_instance" "target_mysql" {
  name             = "target-mysql-${random_id.suffix.hex}"
  database_version = var.target_database_version
  region           = var.region

  settings {
    tier                        = var.target_database_tier
    availability_type           = "REGIONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.target_database_storage_size
    disk_autoresize             = true
    disk_autoresize_limit       = 0

    # Enable binary logging for replication
    database_flags {
      name  = "log_bin"
      value = "on"
    }

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.region
      binary_log_enabled             = true
      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
    }

    # IP configuration for secure access
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.network.self_link
      enable_private_path_for_google_cloud_services = true
    }

    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM
      update_track = "stable"
    }

    # Enable deletion protection
    deletion_protection_enabled = true
  }

  # Apply labels
  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud SQL database
resource "google_sql_database" "target_database" {
  name     = var.source_database_name
  instance = google_sql_database_instance.target_mysql.name
  charset  = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
}

# Create Cloud Workstations cluster
resource "google_workstations_workstation_cluster" "db_migration_cluster" {
  provider = google-beta

  workstation_cluster_id = var.workstation_cluster_name
  location               = var.region
  
  network    = data.google_compute_network.network.id
  subnetwork = data.google_compute_subnetwork.subnet.id

  # Enable private cluster for security
  private_cluster_config {
    enable_private_endpoint = var.enable_private_ip
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create workstation configuration
resource "google_workstations_workstation_config" "db_migration_config" {
  provider = google-beta

  workstation_config_id   = var.workstation_config_name
  workstation_cluster_id  = google_workstations_workstation_cluster.db_migration_cluster.workstation_cluster_id
  location                = var.region

  # Configure the workstation container
  container {
    image = "us-docker.pkg.dev/google-appengine/workstations-images/code-oss:latest"
    
    # Environment variables for database migration
    env = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      ZONE       = var.zone
    }
  }

  # Configure persistent directories
  persistent_directories {
    mount_path = "/home/user/migration-workspace"
    gce_persistent_disk {
      size_gb = var.workstation_persistent_disk_size
      fs_type = "ext4"
    }
  }

  # Configure host settings
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb           = var.workstation_boot_disk_size
      disable_public_ip_addresses = var.enable_private_ip
      
      # Configure service account with necessary permissions
      service_account = google_service_account.workstation_service_account.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }

  # Configure timeouts
  idle_timeout    = "${var.workstation_idle_timeout}s"
  running_timeout = "${var.workstation_running_timeout}s"

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create service account for workstations
resource "google_service_account" "workstation_service_account" {
  account_id   = "workstation-sa-${random_id.suffix.hex}"
  display_name = "Cloud Workstations Service Account"
  description  = "Service account for Cloud Workstations in database migration project"
}

# Grant necessary permissions to workstation service account
resource "google_project_iam_member" "workstation_permissions" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/cloudsql.client",
    "roles/datamigration.admin",
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudbuild.builds.editor"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workstation_service_account.email}"
}

# Create Database Migration Service connection profile for source database
resource "google_database_migration_service_connection_profile" "source_profile" {
  provider = google-beta

  location              = var.region
  connection_profile_id = "source-db-profile-${random_id.suffix.hex}"
  display_name          = "Source Database Profile"
  
  mysql {
    host     = var.source_database_host
    port     = var.source_database_port
    username = var.source_database_user
    password = var.source_database_password
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create Database Migration Service connection profile for target database
resource "google_database_migration_service_connection_profile" "target_profile" {
  provider = google-beta

  location              = var.region
  connection_profile_id = "target-db-profile-${random_id.suffix.hex}"
  display_name          = "Target Cloud SQL Profile"
  
  cloudsql {
    cloud_sql_id = google_sql_database_instance.target_mysql.connection_name
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create custom IAM role for database migration team
resource "google_project_iam_custom_role" "database_migration_developer" {
  role_id     = "databaseMigrationDeveloper"
  title       = "Database Migration Developer"
  description = "Custom role for database migration team members"
  
  permissions = [
    "workstations.workstations.use",
    "workstations.workstations.create",
    "workstations.workstations.delete",
    "workstations.workstations.get",
    "workstations.workstations.list",
    "datamigration.migrationjobs.create",
    "datamigration.migrationjobs.get",
    "datamigration.migrationjobs.list",
    "datamigration.migrationjobs.update",
    "secretmanager.versions.access",
    "cloudsql.instances.connect",
    "cloudsql.instances.get",
    "logging.logEntries.create",
    "monitoring.metricDescriptors.list",
    "monitoring.timeSeries.list"
  ]
}

# Assign custom role to migration team members
resource "google_project_iam_member" "migration_team_members" {
  for_each = toset(var.migration_team_members)
  
  project = var.project_id
  role    = google_project_iam_custom_role.database_migration_developer.name
  member  = "user:${each.value}"
}

# Create Cloud Build trigger for CI/CD pipeline
resource "google_cloudbuild_trigger" "db_migration_pipeline" {
  count = var.enable_cloud_build ? 1 : 0

  name        = var.cloud_build_trigger_name
  description = "CI/CD pipeline for database migration workstation images"
  
  github {
    owner = "your-org"  # Replace with your GitHub organization
    name  = "db-migration-workstations"  # Replace with your repository name
    
    push {
      branch = "main"
    }
  }

  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}/migration-workstation:latest",
        "."
      ]
    }

    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}/migration-workstation:latest"
      ]
    }

    step {
      name = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}/migration-workstation:latest"
      entrypoint = "bash"
      args = [
        "-c",
        "gcloud database-migration migration-jobs list --location=${var.region} || echo 'No active migration jobs'"
      ]
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create log sink for audit logging
resource "google_logging_project_sink" "audit_sink" {
  count = var.enable_audit_logging ? 1 : 0

  name        = "db-migration-audit-sink"
  description = "Audit logging sink for database migration activities"
  
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"
  
  filter = <<EOF
(protoPayload.serviceName="workstations.googleapis.com" OR
 protoPayload.serviceName="datamigration.googleapis.com" OR
 protoPayload.serviceName="secretmanager.googleapis.com") AND
protoPayload.methodName!="google.logging.v2.LoggingServiceV2.ListLogEntries"
EOF

  unique_writer_identity = true
}

# Create Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  count = var.enable_audit_logging ? 1 : 0

  name          = "db-migration-audit-logs-${random_id.suffix.hex}"
  location      = var.region
  force_destroy = true

  # Enable versioning for audit trail
  versioning {
    enabled = true
  }

  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  labels = var.labels
}

# Grant log sink write access to audit logs bucket
resource "google_storage_bucket_iam_member" "audit_logs_writer" {
  count = var.enable_audit_logging ? 1 : 0

  bucket = google_storage_bucket.audit_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_sink[0].writer_identity
}

# Create monitoring dashboard for database migration
resource "google_monitoring_dashboard" "db_migration_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Database Migration Monitoring"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Workstation Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"workstations.googleapis.com/workstation\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              timeshiftDuration = "0s"
            }
          }
        }
      ]
    }
  })
}

# Create notification channel for alerts
resource "google_monitoring_notification_channel" "email_channel" {
  count = length(var.migration_team_members) > 0 ? 1 : 0

  display_name = "Database Migration Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.migration_team_members[0]  # Use first team member as default
  }
}

# Create alert policy for failed migration jobs
resource "google_monitoring_alert_policy" "migration_job_failure" {
  count = var.enable_audit_logging ? 1 : 0

  display_name = "Database Migration Job Failure"
  combiner     = "OR"
  
  conditions {
    display_name = "Migration job failed"
    
    condition_threshold {
      filter         = "resource.type=\"datamigration.googleapis.com/MigrationJob\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = length(var.migration_team_members) > 0 ? [google_monitoring_notification_channel.email_channel[0].name] : []

  depends_on = [google_project_service.required_apis]
}