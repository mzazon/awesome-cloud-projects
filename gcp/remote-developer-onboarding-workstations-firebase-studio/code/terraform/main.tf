# Main Infrastructure Configuration
# Remote Developer Onboarding with Cloud Workstations and Firebase Studio

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix
  cluster_name_unique           = "${var.cluster_name}-${random_id.suffix.hex}"
  config_name_unique           = "${var.workstation_config_name}-${random_id.suffix.hex}"
  source_repo_name_unique      = "${var.source_repo_name}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge({
    environment = var.environment
    team        = var.team
    project     = "remote-developer-onboarding"
    managed_by  = "terraform"
  }, var.additional_labels)
  
  # Network configuration
  network_self_link = "projects/${var.project_id}/global/networks/${var.network_name}"
  subnet_self_link  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.subnet_name}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "workstations.googleapis.com",
    "sourcerepo.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "firestore.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbilling.googleapis.com"
  ])
  
  service = each.value
  project = var.project_id
  
  disable_on_destroy = false
  
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

# Create Cloud Source Repository for team templates
resource "google_sourcerepo_repository" "team_templates" {
  depends_on = [time_sleep.wait_for_apis]
  
  name    = local.source_repo_name_unique
  project = var.project_id
  
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# Create custom IAM role for workstation developers
resource "google_project_iam_custom_role" "workstation_developer" {
  depends_on = [time_sleep.wait_for_apis]
  
  role_id     = "workstationDeveloper"
  title       = "Workstation Developer"
  description = "Custom role for developers using Cloud Workstations"
  stage       = "GA"
  
  permissions = [
    "workstations.workstations.use",
    "workstations.workstations.create",
    "workstations.workstations.list",
    "workstations.workstations.get",
    "workstations.workstations.start",
    "workstations.workstations.stop",
    "source.repos.get",
    "source.repos.list",
    "logging.logEntries.create",
    "monitoring.metricDescriptors.list",
    "monitoring.timeSeries.list"
  ]
}

# Grant IAM permissions to developer users
resource "google_project_iam_member" "developer_workstation_access" {
  for_each = toset(var.developer_users)
  
  project = var.project_id
  role    = google_project_iam_custom_role.workstation_developer.name
  member  = "user:${each.value}"
  
  depends_on = [google_project_iam_custom_role.workstation_developer]
}

# Grant source repository access to developers
resource "google_project_iam_member" "developer_source_access" {
  for_each = toset(var.developer_users)
  
  project = var.project_id
  role    = "roles/source.reader"
  member  = "user:${each.value}"
}

# Grant admin permissions to admin users
resource "google_project_iam_member" "admin_workstation_access" {
  for_each = toset(var.admin_users)
  
  project = var.project_id
  role    = "roles/workstations.admin"
  member  = "user:${each.value}"
}

# Create workstation cluster with network configuration
resource "google_workstations_workstation_cluster" "developer_cluster" {
  depends_on = [time_sleep.wait_for_apis]
  
  provider = google-beta
  
  workstation_cluster_id = local.cluster_name_unique
  location               = var.region
  project                = var.project_id
  
  display_name = "Developer Workstations Cluster"
  
  network = local.network_self_link
  subnetwork = local.subnet_self_link
  
  # Enable private endpoint for enhanced security
  private_cluster_config {
    enable_private_endpoint = var.enable_private_endpoint
  }
  
  labels = local.common_labels
  
  annotations = {
    "cluster-purpose" = "remote-development"
    "team-access"     = "engineering"
  }
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [google_workstations_workstation_cluster.developer_cluster]
  
  create_duration = "30s"
}

# Create comprehensive workstation configuration with development tools
resource "google_workstations_workstation_config" "fullstack_dev_config" {
  depends_on = [time_sleep.wait_for_cluster]
  
  provider = google-beta
  
  workstation_config_id = local.config_name_unique
  workstation_cluster_id = google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id
  location = var.region
  project = var.project_id
  
  display_name = "Full-Stack Developer Environment"
  
  # Machine configuration
  host {
    gce_instance {
      machine_type                = var.machine_type
      boot_disk_size_gb          = 50
      disable_public_ip_addresses = var.enable_private_endpoint
      
      # Enable nested virtualization for Docker
      enable_nested_virtualization = true
      
      # Configure service account with necessary permissions
      service_account = google_service_account.workstation_service_account.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
  
  # Persistent storage configuration
  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb        = var.persistent_disk_size_gb
      fs_type        = "ext4"
      disk_type      = "pd-standard"
      reclaim_policy = "DELETE"
    }
  }
  
  # Container configuration with development tools
  container {
    image = var.workstation_container_image
    
    # Environment variables for development tools
    env = {
      NODE_VERSION   = "18"
      PYTHON_VERSION = "3.11"
      GO_VERSION     = "1.21"
      JAVA_VERSION   = "17"
      
      # Firebase configuration
      FIREBASE_PROJECT_ID = var.project_id
      
      # Source repository configuration
      SOURCE_REPO_NAME = google_sourcerepo_repository.team_templates.name
      
      # Development environment settings
      EDITOR = "code"
      GIT_EDITOR = "code --wait"
    }
    
    # Configure startup command
    run_as_user = "developer"
  }
  
  # Idle timeout configuration
  idle_timeout = "${var.idle_timeout_seconds}s"
  
  # Enable audit logging
  enable_audit_agent = var.enable_audit_logging
  
  labels = local.common_labels
  
  annotations = {
    "config-type"        = "fullstack-development"
    "container-image"    = var.workstation_container_image
    "development-tools"  = "nodejs,python,go,java,docker,git"
  }
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Create service account for workstation instances
resource "google_service_account" "workstation_service_account" {
  depends_on = [time_sleep.wait_for_apis]
  
  account_id   = "workstation-service-account"
  display_name = "Cloud Workstation Service Account"
  description  = "Service account for Cloud Workstation instances"
  project      = var.project_id
}

# Grant necessary permissions to workstation service account
resource "google_project_iam_member" "workstation_sa_permissions" {
  for_each = toset([
    "roles/source.reader",
    "roles/firebase.developer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workstation_service_account.email}"
}

# Initialize Firebase project (if not already initialized)
resource "google_firebase_project" "default" {
  depends_on = [time_sleep.wait_for_apis]
  
  provider = google-beta
  project  = var.project_id
  
  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# Configure Firebase project location
resource "google_firebase_project_location" "default" {
  depends_on = [google_firebase_project.default]
  
  provider = google-beta
  project  = var.project_id
  
  location_id = var.firebase_location
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database for Firebase Studio integration
resource "google_firestore_database" "default" {
  depends_on = [google_firebase_project_location.default]
  
  project                     = var.project_id
  name                       = "(default)"
  location_id                = var.firebase_location
  type                       = "FIRESTORE_NATIVE"
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Create monitoring notification channel for budget alerts
resource "google_monitoring_notification_channel" "email_alert" {
  count = length(var.admin_users) > 0 ? 1 : 0
  
  depends_on = [time_sleep.wait_for_apis]
  
  display_name = "Developer Onboarding Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.admin_users[0]  # Use first admin as primary contact
  }
  
  description = "Email notification channel for developer onboarding infrastructure alerts"
  
  user_labels = local.common_labels
}

# Create billing budget with alerts
resource "google_billing_budget" "developer_workstations_budget" {
  count = length(var.admin_users) > 0 ? 1 : 0
  
  depends_on = [time_sleep.wait_for_apis]
  
  billing_account = data.google_billing_account.account.id
  display_name    = "Developer Workstations Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    services = [
      "services/6F81-5844-456A",  # Compute Engine
      "services/95FF-2EF5-5EA1"   # Cloud Workstations
    ]
    
    labels = {
      "team" = [var.team]
    }
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units        = tostring(var.budget_amount)
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis      = "CURRENT_SPEND"
    }
  }
  
  dynamic "all_updates_rule" {
    for_each = length(var.admin_users) > 0 ? [1] : []
    content {
      monitoring_notification_channels = [
        google_monitoring_notification_channel.email_alert[0].name
      ]
      disable_default_iam_recipients = false
    }
  }
}

# Get billing account information
data "google_billing_account" "account" {
  billing_account = data.google_project.current.billing_account
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create monitoring dashboard for workstation metrics
resource "google_monitoring_dashboard" "workstation_dashboard" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  depends_on = [time_sleep.wait_for_apis]
  
  dashboard_json = jsonencode({
    displayName = "Developer Workstations Dashboard"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Active Workstations"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"${local.cluster_name_unique}.*\""
                  aggregation = {
                    alignmentPeriod  = "60s"
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
          xPos   = 6
          widget = {
            title = "Workstation CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"${local.cluster_name_unique}.*\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.labels.instance_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Workstation Usage by User"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"workstations.googleapis.com/Workstation\" AND metric.type=\"workstations.googleapis.com/workstation/active_time\""
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.labels.workstation_id"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = {
                label = "Active Time (seconds)"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
    
    labels = local.common_labels
  })
}

# Create log-based metric for workstation creation events
resource "google_logging_metric" "workstation_creation_metric" {
  depends_on = [time_sleep.wait_for_apis]
  
  name   = "workstation_creation_count"
  filter = "resource.type=\"workstations.googleapis.com/Workstation\" AND protoPayload.methodName=\"google.cloud.workstations.v1beta.Workstations.CreateWorkstation\""
  
  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Workstation Creation Count"
  }
  
  label_extractors = {
    "workstation_id" = "EXTRACT(resource.labels.workstation_id)"
    "user_email"     = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}

# Create alerting policy for workstation creation monitoring
resource "google_monitoring_alert_policy" "workstation_creation_alert" {
  count = length(var.admin_users) > 0 ? 1 : 0
  
  depends_on = [google_logging_metric.workstation_creation_metric]
  
  display_name = "High Workstation Creation Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Workstation creation rate"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/workstation_creation_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.email_alert[0].name
  ]
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Create Cloud Scheduler job for workstation cleanup (optional)
resource "google_cloud_scheduler_job" "workstation_cleanup" {
  depends_on = [time_sleep.wait_for_apis]
  
  name             = "workstation-idle-cleanup"
  description      = "Cleanup idle workstations to optimize costs"
  schedule         = "0 2 * * *"  # Run daily at 2 AM
  time_zone        = "UTC"
  attempt_deadline = "60s"
  
  region = var.region
  
  http_target {
    http_method = "POST"
    uri         = "https://workstations.googleapis.com/v1beta/projects/${var.project_id}/locations/${var.region}/workstationClusters/${google_workstations_workstation_cluster.developer_cluster.workstation_cluster_id}/workstationConfigs/${google_workstations_workstation_config.fullstack_dev_config.workstation_config_id}/workstations:listWorkstations"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    oauth_token {
      service_account_email = google_service_account.workstation_service_account.email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  retry_config {
    retry_count = 3
  }
}