# Enable required Google Cloud APIs for the migration platform
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "alloydb.googleapis.com",
    "datamigration.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels applied to all resources
  common_labels = {
    environment    = var.environment
    team          = var.team
    project       = var.project_name
    created_by    = "terraform"
    recipe        = "multi-database-migration-workflows"
  }

  # Resource naming with unique suffix
  name_suffix = random_id.suffix.hex
  instance_template_name = "migration-template-${local.name_suffix}"
  cloudsql_instance_name = "mysql-target-${local.name_suffix}"
  alloydb_cluster_name   = "postgres-cluster-${local.name_suffix}"
  bucket_name           = "${var.project_id}-migration-bucket-${local.name_suffix}"
}

# Create VPC network for secure migration traffic
resource "google_compute_network" "migration_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"

  depends_on = [google_project_service.required_apis]
}

# Create subnet for migration infrastructure
resource "google_compute_subnetwork" "migration_subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.migration_network.id

  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true

  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule to allow internal communication between migration workers
resource "google_compute_firewall" "migration_internal" {
  name    = "migration-internal-${local.name_suffix}"
  network = google_compute_network.migration_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3306", "5432", "8080"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["migration-worker"]
}

# Firewall rule to allow SSH access to migration workers
resource "google_compute_firewall" "migration_ssh" {
  name    = "migration-ssh-${local.name_suffix}"
  network = google_compute_network.migration_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP range
  target_tags   = ["migration-worker"]
}

# Cloud Storage bucket for migration artifacts and logs
resource "google_storage_bucket" "migration_bucket" {
  name     = local.bucket_name
  location = var.migration_bucket_location

  # Prevent accidental deletion of migration data
  force_destroy = false

  versioning {
    enabled = true
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

  depends_on = [google_project_service.required_apis]
}

# Instance template for migration workers with optimal configurations
resource "google_compute_instance_template" "migration_workers" {
  name_prefix  = "${local.instance_template_name}-"
  machine_type = var.worker_machine_type
  region       = var.region

  # Boot disk configuration with SSD for better performance
  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.worker_disk_size
    disk_type    = "pd-ssd"
  }

  # Network configuration
  network_interface {
    network    = google_compute_network.migration_network.id
    subnetwork = google_compute_subnetwork.migration_subnet.id
    # No external IP - workers access internet through Cloud NAT
  }

  # Service account with necessary permissions for migration operations
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  # Startup script to install database clients and monitoring tools
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y mysql-client postgresql-client python3-pip curl
    pip3 install google-cloud-monitoring google-cloud-logging google-cloud-storage
    
    # Configure logging for migration operations
    mkdir -p /var/log/migration
    chmod 755 /var/log/migration
    
    # Install Cloud SQL Proxy for secure database connections
    curl -o cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64
    chmod +x cloud_sql_proxy
    mv cloud_sql_proxy /usr/local/bin/
    
    echo "Migration worker initialized successfully" | logger -t migration-worker
  EOF

  tags = ["migration-worker"]

  labels = local.common_labels

  # Create a new template version when configuration changes
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.required_apis]
}

# Managed instance group for auto-scaling migration workers
resource "google_compute_region_instance_group_manager" "migration_workers" {
  name   = "migration-workers-${local.name_suffix}"
  region = var.region

  base_instance_name = "migration-worker"
  target_size        = 0 # Start with no instances, scale based on demand

  version {
    instance_template = google_compute_instance_template.migration_workers.id
  }

  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_health_check.migration_worker_health.id
    initial_delay_sec = 300
  }

  # Update policy for rolling updates
  update_policy {
    type                         = "PROACTIVE"
    minimal_action              = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed             = 2
    max_unavailable_fixed       = 1
  }

  depends_on = [google_project_service.required_apis]
}

# Health check for migration workers
resource "google_compute_health_check" "migration_worker_health" {
  name               = "migration-worker-health-${local.name_suffix}"
  check_interval_sec = 30
  timeout_sec        = 10
  healthy_threshold  = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "22"
  }
}

# Autoscaler for migration workers based on CPU utilization
resource "google_compute_region_autoscaler" "migration_workers" {
  name   = "migration-workers-autoscaler-${local.name_suffix}"
  region = var.region
  target = google_compute_region_instance_group_manager.migration_workers.id

  autoscaling_policy {
    max_replicas    = var.max_worker_instances
    min_replicas    = 0
    cooldown_period = var.cooldown_period_seconds

    cpu_utilization {
      target = var.autoscaling_cpu_target
    }

    # Scale based on load balancing utilization for migration tasks
    load_balancing_utilization {
      target = 0.8
    }
  }
}

# Future reservation for migration workloads (Dynamic Workload Scheduler)
resource "google_compute_future_reservation" "migration_capacity" {
  name = "migration-flex-capacity-${local.name_suffix}"
  zone = var.zone

  specific_reservation {
    count = var.reservation_capacity
    instance_properties {
      machine_type = var.worker_machine_type
    }
  }

  planning_status = "PLANNING_STATUS_PLANNED"

  depends_on = [google_project_service.required_apis]
}

# Cloud SQL instance for MySQL migrations
resource "google_sql_database_instance" "mysql_target" {
  name             = local.cloudsql_instance_name
  database_version = var.cloudsql_database_version
  region           = var.region

  deletion_protection = var.enable_deletion_protection

  settings {
    tier              = var.cloudsql_tier
    availability_type = "REGIONAL" # High availability configuration
    disk_type         = "PD_SSD"
    disk_size         = var.cloudsql_storage_size
    disk_autoresize   = true

    # Network configuration for private IP
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                              = google_compute_network.migration_network.id
      enable_private_path_for_google_cloud_services = true
    }

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                    = "03:00"
      point_in_time_recovery_enabled = true
      binary_log_enabled            = true
      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
    }

    # Maintenance window
    maintenance_window {
      day          = 7 # Sunday
      hour         = 4
      update_track = "stable"
    }

    # Database flags for optimal migration performance
    database_flags {
      name  = "innodb_buffer_pool_size"
      value = "75%"
    }

    database_flags {
      name  = "innodb_log_file_size"
      value = "268435456" # 256MB
    }

    user_labels = local.common_labels
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Database user for migration operations
resource "google_sql_user" "migration_user" {
  name     = "migration-user"
  instance = google_sql_database_instance.mysql_target.name
  password = var.cloudsql_migration_user_password
}

# Sample database for migration target
resource "google_sql_database" "sample_db" {
  name     = "sample_db"
  instance = google_sql_database_instance.mysql_target.name
}

# AlloyDB cluster for PostgreSQL migrations
resource "google_alloydb_cluster" "postgres_target" {
  provider   = google-beta
  cluster_id = local.alloydb_cluster_name
  location   = var.region
  network    = google_compute_network.migration_network.id

  database_type    = "POSTGRES"
  initial_user {
    user     = "postgres"
    password = var.cloudsql_migration_user_password
  }

  # Automated backup configuration
  automated_backup_policy {
    backup_window = "03:00-04:00"
    enabled       = true
    
    weekly_schedule {
      start_times {
        hours   = 3
        minutes = 0
      }
      days_of_week = ["SUNDAY"]
    }

    quantity_based_retention {
      count = var.backup_retention_days
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# AlloyDB primary instance
resource "google_alloydb_instance" "postgres_primary" {
  provider    = google-beta
  cluster     = google_alloydb_cluster.postgres_target.name
  instance_id = "${local.alloydb_cluster_name}-primary"
  
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.alloydb_cpu_count
  }

  depends_on = [google_alloydb_cluster.postgres_target]
}

# Private service connection for Cloud SQL and AlloyDB
resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address-${local.name_suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.migration_network.id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.migration_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  depends_on = [google_project_service.required_apis]
}

# Database Migration Service connection profiles
resource "google_database_migration_service_connection_profile" "source_mysql" {
  location              = var.region
  connection_profile_id = "source-mysql-${local.name_suffix}"
  display_name         = "Source MySQL Database"

  mysql {
    host     = var.source_mysql_host
    port     = var.source_mysql_port
    username = var.source_db_username
    password = var.source_db_password

    ssl {
      type = "SERVER_ONLY"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_database_migration_service_connection_profile" "dest_cloudsql" {
  location              = var.region
  connection_profile_id = "dest-cloudsql-${local.name_suffix}"
  display_name         = "Destination Cloud SQL"

  cloudsql {
    cloud_sql_id = google_sql_database_instance.mysql_target.connection_name
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_database_migration_service_connection_profile" "source_postgres" {
  location              = var.region
  connection_profile_id = "source-postgres-${local.name_suffix}"
  display_name         = "Source PostgreSQL Database"

  postgresql {
    host     = var.source_postgres_host
    port     = var.source_postgres_port
    username = var.source_db_username
    password = var.source_db_password

    ssl {
      type = "SERVER_ONLY"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_database_migration_service_connection_profile" "dest_alloydb" {
  location              = var.region
  connection_profile_id = "dest-alloydb-${local.name_suffix}"
  display_name         = "Destination AlloyDB"

  alloydb {
    cluster_id = google_alloydb_cluster.postgres_target.name
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM service account for Cloud Functions
resource "google_service_account" "migration_orchestrator" {
  account_id   = "migration-orchestrator-${local.name_suffix}"
  display_name = "Migration Orchestrator Service Account"
  description  = "Service account for migration orchestration Cloud Function"

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for migration orchestrator
resource "google_project_iam_member" "orchestrator_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.migration_orchestrator.email}"
}

resource "google_project_iam_member" "orchestrator_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.migration_orchestrator.email}"
}

resource "google_project_iam_member" "orchestrator_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.migration_orchestrator.email}"
}

# Cloud Function for migration orchestration
resource "google_storage_bucket_object" "orchestrator_source" {
  name   = "orchestrator-source-${local.name_suffix}.zip"
  bucket = google_storage_bucket.migration_bucket.name
  source = data.archive_file.orchestrator_source.output_path

  depends_on = [google_storage_bucket.migration_bucket]
}

# Create source code archive for Cloud Function
data "archive_file" "orchestrator_source" {
  type        = "zip"
  output_path = "/tmp/orchestrator-source-${local.name_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }

  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_cloudfunctions2_function" "migration_orchestrator" {
  name     = "migration-orchestrator-${local.name_suffix}"
  location = var.region

  build_config {
    runtime     = "python39"
    entry_point = "orchestrate_migration"
    
    source {
      storage_source {
        bucket = google_storage_bucket.migration_bucket.name
        object = google_storage_bucket_object.orchestrator_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    available_memory      = "256M"
    timeout_seconds       = 300
    service_account_email = google_service_account.migration_orchestrator.email

    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.orchestrator_source
  ]
}

# Cloud Function IAM for public access (for demo purposes)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.migration_orchestrator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Monitoring dashboard for migration metrics
resource "google_monitoring_dashboard" "migration_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Database Migration Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Migration Worker CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"migration-worker-.*\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Migration Progress"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
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

# Cloud Monitoring alert policy for migration failures
resource "google_monitoring_alert_policy" "migration_worker_failure" {
  display_name = "Migration Worker Failure Alert"
  
  conditions {
    display_name = "High error rate"
    
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"migration-worker-.*\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}