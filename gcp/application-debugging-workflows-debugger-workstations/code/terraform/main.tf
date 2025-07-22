# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  
  # Resource names with unique suffixes
  workstation_cluster_name       = coalesce(var.workstation_cluster_name, "${var.resource_prefix}-cluster-${local.resource_suffix}")
  workstation_config_name        = coalesce(var.workstation_config_name, "${var.resource_prefix}-config-${local.resource_suffix}")
  workstation_instance_name      = coalesce(var.workstation_instance_name, "${var.resource_prefix}-instance-${local.resource_suffix}")
  artifact_registry_repo_name    = coalesce(var.artifact_registry_repository_name, "${var.resource_prefix}-tools-${local.resource_suffix}")
  cloud_run_service_name         = coalesce(var.cloud_run_service_name, "${var.resource_prefix}-app-${local.resource_suffix}")
  debug_tools_image_name         = "${var.debug_tools_image_name}-${local.resource_suffix}"
  
  # Combined labels
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
    suffix      = local.resource_suffix
  })
  
  # Container image URIs
  debug_tools_image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${local.artifact_registry_repo_name}/${local.debug_tools_image_name}:${var.debug_tools_image_tag}"
  sample_app_image_uri  = "${var.region}-docker.pkg.dev/${var.project_id}/${local.artifact_registry_repo_name}/${local.cloud_run_service_name}:latest"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Artifact Registry repository for debug tools and sample applications
resource "google_artifact_registry_repository" "debug_tools_repo" {
  depends_on = [google_project_service.required_apis]
  
  location      = var.region
  repository_id = local.artifact_registry_repo_name
  description   = var.artifact_registry_description
  format        = "DOCKER"
  
  labels = local.common_labels
  
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    
    most_recent_versions {
      keep_count = 10
    }
  }
  
  cleanup_policies {
    id     = "delete-old-versions"
    action = "DELETE"
    
    condition {
      older_than = "30d"
    }
  }
}

# Create service account for Cloud Workstations
resource "google_service_account" "workstation_sa" {
  depends_on = [google_project_service.required_apis]
  
  account_id   = "${var.resource_prefix}-workstation-sa-${local.resource_suffix}"
  display_name = "Cloud Workstations Service Account for ${var.resource_prefix}"
  description  = "Service account for Cloud Workstations debugging workflow"
  
  project = var.project_id
}

# Grant necessary permissions to the workstation service account
resource "google_project_iam_member" "workstation_sa_permissions" {
  depends_on = [google_service_account.workstation_sa]
  
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/run.viewer",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/cloudbuild.builds.viewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

# Create service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  depends_on = [google_project_service.required_apis]
  
  account_id   = "${var.resource_prefix}-run-sa-${local.resource_suffix}"
  display_name = "Cloud Run Service Account for ${var.resource_prefix}"
  description  = "Service account for Cloud Run sample application"
  
  project = var.project_id
}

# Grant necessary permissions to the Cloud Run service account
resource "google_project_iam_member" "cloud_run_sa_permissions" {
  depends_on = [google_service_account.cloud_run_sa]
  
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudsql.client"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Get the default VPC network
data "google_compute_network" "default" {
  name    = var.network_name
  project = var.project_id
}

# Get the default subnet
data "google_compute_subnetwork" "default" {
  name    = var.subnet_name
  region  = var.region
  project = var.project_id
}

# Create Cloud Workstations cluster
resource "google_workstations_workstation_cluster" "debug_cluster" {
  depends_on = [google_project_service.required_apis]
  
  provider = google-beta
  
  workstation_cluster_id = local.workstation_cluster_name
  location               = var.region
  
  network    = data.google_compute_network.default.id
  subnetwork = data.google_compute_subnetwork.default.id
  
  labels = local.common_labels
  
  # Enable private cluster for security
  private_cluster_config {
    enable_private_endpoint = false
    cluster_hostname        = ""
  }
  
  # Configure domain settings
  domain_config {
    domain = "${local.workstation_cluster_name}.${var.region}.workstations.googleusercontent.com"
  }
  
  # Annotations for additional metadata
  annotations = {
    "purpose"     = "debugging-workflow"
    "environment" = var.environment
    "managed-by"  = "terraform"
  }
  
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create Cloud Workstations configuration
resource "google_workstations_workstation_config" "debug_config" {
  depends_on = [
    google_workstations_workstation_cluster.debug_cluster,
    google_artifact_registry_repository.debug_tools_repo
  ]
  
  provider = google-beta
  
  workstation_config_id = local.workstation_config_name
  location              = var.region
  workstation_cluster_id = google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id
  
  labels = local.common_labels
  
  # Host configuration
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb          = var.workstation_disk_size_gb
      disable_public_ip_addresses = false
      
      # Configure disk
      persistent_disks {
        size_gb       = var.workstation_disk_size_gb
        disk_type     = var.workstation_disk_type
        source_image  = "projects/cloud-workstations-images/global/images/workstations-ubuntu-2204"
      }
      
      # Assign service account
      service_account = coalesce(var.workstation_service_account_email, google_service_account.workstation_sa.email)
      
      # Configure scopes
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
      
      # Configure network tags
      tags = ["workstation", "debugging", var.environment]
    }
  }
  
  # Container configuration with custom debug tools image
  container {
    image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
    
    # Environment variables for debugging
    env = {
      "DEBUG_MODE"        = "enabled"
      "LOG_LEVEL"         = "debug"
      "ARTIFACT_REGISTRY" = local.artifact_registry_repo_name
      "PROJECT_ID"        = var.project_id
      "REGION"           = var.region
    }
    
    # Working directory
    working_dir = "/home/codeoss"
    
    # Run as non-root user
    run_as_user = 1000
  }
  
  # Timeout configurations
  idle_timeout    = "${var.workstation_idle_timeout}s"
  running_timeout = "${var.workstation_running_timeout}s"
  
  # Encryption configuration
  encryption_key {
    kms_key = ""
  }
  
  # Persistent directories
  persistent_directories {
    mount_path = "/home/codeoss/workspace"
    
    gce_pd {
      size_gb   = 100
      fs_type   = "ext4"
      disk_type = "pd-standard"
    }
  }
  
  # Annotations for additional metadata
  annotations = {
    "purpose"      = "debugging-workflow"
    "environment"  = var.environment
    "machine-type" = var.workstation_machine_type
    "managed-by"   = "terraform"
  }
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# Create Cloud Workstations instance
resource "google_workstations_workstation" "debug_instance" {
  depends_on = [google_workstations_workstation_config.debug_config]
  
  provider = google-beta
  
  workstation_id         = local.workstation_instance_name
  location              = var.region
  workstation_cluster_id = google_workstations_workstation_cluster.debug_cluster.workstation_cluster_id
  workstation_config_id  = google_workstations_workstation_config.debug_config.workstation_config_id
  
  labels = local.common_labels
  
  # Annotations for additional metadata
  annotations = {
    "purpose"     = "debugging-workflow"
    "environment" = var.environment
    "created-by"  = "terraform"
  }
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Create Cloud Run service for sample application
resource "google_cloud_run_v2_service" "sample_app" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.cloud_run_service_name
  location = var.region
  
  labels = local.common_labels
  
  template {
    labels = local.common_labels
    
    # Configure scaling
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Configure service account
    service_account = coalesce(var.cloud_run_service_account_email, google_service_account.cloud_run_sa.email)
    
    containers {
      image = var.cloud_run_image
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        
        cpu_idle          = false
        startup_cpu_boost = true
      }
      
      # Configure ports
      ports {
        container_port = var.cloud_run_port
        name           = "http1"
      }
      
      # Environment variables
      env {
        name  = "NODE_ENV"
        value = "development"
      }
      
      env {
        name  = "LOG_LEVEL"
        value = "debug"
      }
      
      env {
        name  = "PORT"
        value = tostring(var.cloud_run_port)
      }
      
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      # Health check configuration
      liveness_probe {
        http_get {
          path = "/health"
          port = var.cloud_run_port
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      startup_probe {
        http_get {
          path = "/health"
          port = var.cloud_run_port
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
    }
    
    # Configure VPC access
    vpc_access {
      egress = "ALL_TRAFFIC"
      
      network_interfaces {
        network    = data.google_compute_network.default.id
        subnetwork = data.google_compute_subnetwork.default.id
      }
    }
    
    # Configure execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Timeout configuration
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Create IAM policy for Cloud Run service to allow unauthenticated access
resource "google_cloud_run_service_iam_member" "public_access" {
  depends_on = [google_cloud_run_v2_service.sample_app]
  
  location = google_cloud_run_v2_service.sample_app.location
  service  = google_cloud_run_v2_service.sample_app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create Cloud Logging sink for workstation activities (optional)
resource "google_logging_project_sink" "workstation_debug_sink" {
  count = var.enable_logging ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  name        = "${var.resource_prefix}-workstation-sink-${local.resource_suffix}"
  description = "Logging sink for workstation debugging activities"
  
  # Destination for logs (Cloud Storage bucket would be created separately)
  destination = "storage.googleapis.com/${var.resource_prefix}-debug-logs-${local.resource_suffix}"
  
  # Filter for workstation-related logs
  filter = <<-EOT
    resource.type="gce_instance"
    resource.labels.instance_name:workstation
    OR
    resource.type="cloud_run_revision"
    resource.labels.service_name="${local.cloud_run_service_name}"
  EOT
  
  # Configure exclusions
  exclusions {
    name        = "exclude-health-checks"
    description = "Exclude health check logs"
    filter      = "httpRequest.requestUrl:health"
  }
  
  # Unique writer identity
  unique_writer_identity = true
}

# Create Cloud Monitoring dashboard for debugging workflow (optional)
resource "google_monitoring_dashboard" "debug_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  dashboard_json = jsonencode({
    displayName = "Debugging Workflow Dashboard"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Workstation CPU Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND resource.label.instance_name:workstation"
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
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${local.cloud_run_service_name}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
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
}

# Create Cloud Scheduler job for automatic workstation shutdown (optional)
resource "google_cloud_scheduler_job" "workstation_shutdown" {
  count = var.enable_auto_shutdown ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  name        = "${var.resource_prefix}-auto-shutdown-${local.resource_suffix}"
  description = "Automatically shutdown workstations during non-business hours"
  region      = var.region
  schedule    = var.auto_shutdown_schedule
  time_zone   = "UTC"
  
  # HTTP target to call Cloud Functions or Cloud Run service
  http_target {
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/shutdown-workstations"
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id = var.project_id
      region     = var.region
      cluster_id = local.workstation_cluster_name
    }))
  }
}

# Create firewall rule for workstation access (if needed)
resource "google_compute_firewall" "workstation_access" {
  name    = "${var.resource_prefix}-workstation-access-${local.resource_suffix}"
  network = data.google_compute_network.default.name
  
  description = "Allow access to Cloud Workstations for debugging"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080", "9229"]
  }
  
  source_ranges = var.allowed_ingress_cidr_blocks
  target_tags   = ["workstation"]
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for debug artifacts (optional)
resource "google_storage_bucket" "debug_artifacts" {
  name     = "${var.resource_prefix}-debug-artifacts-${local.resource_suffix}"
  location = var.region
  
  labels = local.common_labels
  
  # Configure lifecycle policy
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning
  versioning {
    enabled = true
  }
  
  # Configure uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Enable logging
  logging {
    log_bucket = "${var.resource_prefix}-access-logs-${local.resource_suffix}"
  }
  
  depends_on = [google_project_service.required_apis]
}