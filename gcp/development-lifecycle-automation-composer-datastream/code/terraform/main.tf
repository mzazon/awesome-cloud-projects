# Main Terraform Configuration
# Development Lifecycle Automation with Cloud Composer and Datastream

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-${local.resource_suffix}"
  artifact_repo   = "secure-containers-${local.resource_suffix}"
  db_instance     = "dev-database-${local.resource_suffix}"
  
  # Combined labels
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "development-lifecycle-automation"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "composer.googleapis.com",
    "datastream.googleapis.com",
    "artifactregistry.googleapis.com",
    "workflows.googleapis.com",
    "cloudbuild.googleapis.com",
    "containeranalysis.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "binaryauthorization.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create Cloud Storage bucket for workflow assets
resource "google_storage_bucket" "workflow_assets" {
  name     = local.bucket_name
  location = var.region
  
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = !var.deletion_protection

  versioning {
    enabled = var.enable_versioning
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

  depends_on = [time_sleep.wait_for_apis]
}

# Create organized folder structure in bucket
resource "google_storage_bucket_object" "workflow_folders" {
  for_each = toset([
    "dags/.keep",
    "data/.keep", 
    "policies/.keep",
    "logs/.keep",
    "datastream/.keep"
  ])

  name   = each.key
  bucket = google_storage_bucket.workflow_assets.name
  source = "/dev/null"
}

# Create Artifact Registry repository for secure container images
resource "google_artifact_registry_repository" "container_repo" {
  repository_id = local.artifact_repo
  location      = var.region
  format        = "DOCKER"
  
  description = "Secure container repository with automated scanning"
  
  labels = local.common_labels

  depends_on = [time_sleep.wait_for_apis]
}

# Generate secure database password
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Create Cloud SQL PostgreSQL instance for development database
resource "google_sql_database_instance" "dev_database" {
  name             = local.db_instance
  database_version = var.database_version
  region           = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 20
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "23:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
    }

    maintenance_window {
      day          = 7  # Sunday
      hour         = 2  # 2 AM
      update_track = "stable"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    ip_configuration {
      ipv4_enabled    = !var.enable_private_ip
      private_network = var.enable_private_ip ? google_compute_network.composer_network[0].id : null
      require_ssl     = var.enable_ssl

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    user_labels = local.common_labels
  }

  root_password = random_password.db_password.result

  depends_on = [time_sleep.wait_for_apis]
}

# Create application database
resource "google_sql_database" "app_database" {
  name     = var.database_name
  instance = google_sql_database_instance.dev_database.name
  
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Create VPC network for Cloud Composer (if private IP enabled)
resource "google_compute_network" "composer_network" {
  count = var.enable_private_ip ? 1 : 0
  
  name                    = "${var.resource_prefix}-network"
  auto_create_subnetworks = false
  mtu                     = 1460
}

# Create subnet for Cloud Composer
resource "google_compute_subnetwork" "composer_subnet" {
  count = var.enable_private_ip ? 1 : 0
  
  name          = "${var.resource_prefix}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.composer_network[0].id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }

  private_ip_google_access = true
}

# Create Cloud Composer 3 environment with Apache Airflow 3
resource "google_composer_environment" "intelligent_devops" {
  name   = var.composer_env_name
  region = var.region
  
  labels = local.common_labels

  config {
    node_count = var.composer_node_count

    node_config {
      zone         = var.zone
      machine_type = var.composer_machine_type
      disk_size_gb = var.composer_disk_size
      
      # Use service account with minimal required permissions
      service_account = google_service_account.composer_sa.email

      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]

      tags = ["composer-worker"]
    }

    software_config {
      image_version = var.airflow_version
      
      env_variables = {
        BUCKET_NAME     = google_storage_bucket.workflow_assets.name
        PROJECT_ID      = var.project_id
        ARTIFACT_REPO   = google_artifact_registry_repository.container_repo.repository_id
        REGION          = var.region
        DATABASE_HOST   = google_sql_database_instance.dev_database.private_ip_address
        DATABASE_NAME   = google_sql_database.app_database.name
      }

      pypi_packages = {
        "google-cloud-storage"       = ""
        "google-cloud-bigquery"      = ""
        "google-cloud-monitoring"    = ""
        "google-cloud-workflows"     = ""
        "google-cloud-datastream"    = ""
      }
    }

    dynamic "private_environment_config" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        enable_private_endpoint                = true
        master_ipv4_cidr_block                = "172.16.0.0/28"
        cloud_sql_ipv4_cidr_block             = "10.3.0.0/12"
        cloud_composer_network_ipv4_cidr_block = "10.4.0.0/14"
      }
    }

    dynamic "web_server_network_access_control" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        allowed_ip_range {
          value = "0.0.0.0/0"
          description = "Allow access from anywhere (restrict in production)"
        }
      }
    }
  }

  depends_on = [
    time_sleep.wait_for_apis,
    google_project_iam_member.composer_permissions
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create service account for Cloud Composer
resource "google_service_account" "composer_sa" {
  account_id   = "${var.resource_prefix}-composer-sa"
  display_name = "Cloud Composer Service Account"
  description  = "Service account for Cloud Composer environment with minimal required permissions"
}

# Grant necessary permissions to Composer service account
resource "google_project_iam_member" "composer_permissions" {
  for_each = toset([
    "roles/composer.worker",
    "roles/storage.admin", 
    "roles/artifactregistry.reader",
    "roles/cloudsql.client",
    "roles/datastream.admin",
    "roles/workflows.invoker",
    "roles/cloudbuild.builds.editor",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.composer_sa.email}"
}

# Create Datastream connection profile for source database
resource "google_datastream_connection_profile" "source_profile" {
  display_name          = "${local.db_instance}-profile"
  location              = var.region
  connection_profile_id = "${local.db_instance}-profile"

  postgresql_profile {
    hostname = google_sql_database_instance.dev_database.private_ip_address
    port     = 5432
    username = "postgres"
    password = random_password.db_password.result
    database = google_sql_database.app_database.name
  }

  labels = local.common_labels

  depends_on = [time_sleep.wait_for_apis]
}

# Create Datastream connection profile for Cloud Storage destination
resource "google_datastream_connection_profile" "destination_profile" {
  display_name          = "storage-destination"
  location              = var.region
  connection_profile_id = "storage-destination"

  gcs_profile {
    bucket    = google_storage_bucket.workflow_assets.name
    root_path = "/datastream"
  }

  labels = local.common_labels

  depends_on = [time_sleep.wait_for_apis]
}

# Create Datastream for real-time change data capture
resource "google_datastream_stream" "schema_changes" {
  display_name = "${var.resource_prefix}-changes-stream"
  location     = var.region
  stream_id    = "${var.resource_prefix}-changes-stream"

  source_config {
    source_connection_profile = google_datastream_connection_profile.source_profile.id
    
    postgresql_source_config {
      max_concurrent_backfill_tasks = 1
      publication {
        name = "datastream_publication"
      }
      replication_slot {
        slot = "datastream_slot"
      }
      
      include_objects {
        postgresql_schemas {
          schema = "public"
          postgresql_tables {
            table = "users"
          }
          postgresql_tables {
            table = "orders"
          }
          postgresql_tables {
            table = "products"
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.destination_profile.id
    
    gcs_destination_config {
      path                = "/cdc-data"
      file_rotation_mb    = 100
      file_rotation_interval = "300s"
      
      json_file_format {
        schema_file_format = "AVRO_SCHEMA_FILE"
        compression        = "GZIP"
      }
    }
  }

  labels = local.common_labels

  depends_on = [
    google_datastream_connection_profile.source_profile,
    google_datastream_connection_profile.destination_profile
  ]
}

# Create Cloud Workflow for compliance validation
resource "google_workflows_workflow" "compliance_workflow" {
  name            = "intelligent-deployment-workflow"
  region          = var.region
  description     = "Intelligent deployment workflow with compliance validation"
  service_account = google_service_account.workflow_sa.id

  source_contents = templatefile("${path.module}/workflows/compliance-workflow.yaml", {
    project_id = var.project_id
  })

  labels = local.common_labels

  depends_on = [time_sleep.wait_for_apis]
}

# Create service account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  account_id   = "${var.resource_prefix}-workflow-sa"
  display_name = "Cloud Workflows Service Account"
  description  = "Service account for Cloud Workflows with compliance validation permissions"
}

# Grant permissions to Workflow service account
resource "google_project_iam_member" "workflow_permissions" {
  for_each = toset([
    "roles/workflows.invoker",
    "roles/storage.objectViewer",
    "roles/cloudsql.viewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# Configure Binary Authorization policy for container security
resource "google_binary_authorization_policy" "security_policy" {
  count = var.enable_binary_authorization ? 1 : 0

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.security_attestor[0].name
    ]
  }

  cluster_admission_rules {
    cluster                = "${var.region}.production-cluster"
    evaluation_mode        = "REQUIRE_ATTESTATION"
    enforcement_mode       = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.security_attestor[0].name
    ]
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Create Binary Authorization attestor for security validation
resource "google_binary_authorization_attestor" "security_attestor" {
  count = var.enable_binary_authorization ? 1 : 0

  name = "security-scan-attestor"
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.security_note[0].name
    
    public_keys {
      id = "security-key"
      ascii_armored_pgp_public_key = file("${path.module}/keys/security-key.pub")
    }
  }

  description = "Attestor for security scan validation"
}

# Create Container Analysis note for security attestations
resource "google_container_analysis_note" "security_note" {
  count = var.enable_binary_authorization ? 1 : 0

  name = "security-scan-note"
  
  attestation_authority {
    hint {
      human_readable_name = "Security scan validation"
    }
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Create BigQuery dataset for metrics and monitoring
resource "google_bigquery_dataset" "devops_metrics" {
  count = var.enable_monitoring ? 1 : 0

  dataset_id    = "devops_metrics"
  friendly_name = "DevOps Automation Metrics"
  description   = "Dataset for storing DevOps pipeline metrics and analytics"
  location      = var.region

  delete_contents_on_destroy = !var.deletion_protection

  labels = local.common_labels

  depends_on = [time_sleep.wait_for_apis]
}

# Create BigQuery table for pipeline run metrics
resource "google_bigquery_table" "pipeline_runs" {
  count = var.enable_monitoring ? 1 : 0

  dataset_id = google_bigquery_dataset.devops_metrics[0].dataset_id
  table_id   = "pipeline_runs"

  deletion_protection = var.deletion_protection

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "dag_runs_success"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "dag_runs_failed"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "avg_execution_time_minutes"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "security_scans_blocked"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "deployments_approved"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "compliance_violations"
      type = "INTEGER"
      mode = "NULLABLE"
    }
  ])

  labels = local.common_labels
}

# Create monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email_channel" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  display_name = "DevOps Automation Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Create alerting policy for failed DAG runs
resource "google_monitoring_alert_policy" "dag_failure_alert" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "DAG Failure Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "DAG Run Failures"
    
    condition_threshold {
      filter         = "resource.type=\"composer_environment\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? google_monitoring_notification_channel.email_channel : []
    content {
      notification_channels = [notification_channels.value.name]
    }
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Store sample DAG files in Cloud Storage
resource "google_storage_bucket_object" "sample_dag" {
  name   = "dags/intelligent_cicd_dag.py"
  bucket = google_storage_bucket.workflow_assets.name
  source = "${path.module}/dags/intelligent_cicd_dag.py"
  
  depends_on = [google_storage_bucket_object.workflow_folders]
}

resource "google_storage_bucket_object" "monitoring_dag" {
  name   = "dags/monitoring_dag.py"
  bucket = google_storage_bucket.workflow_assets.name
  source = "${path.module}/dags/monitoring_dag.py"
  
  depends_on = [google_storage_bucket_object.workflow_folders]
}