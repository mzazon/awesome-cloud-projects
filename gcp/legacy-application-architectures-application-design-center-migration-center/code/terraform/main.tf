# Main Terraform configuration for legacy application modernization
# This configuration sets up Migration Center, Application Design Center, 
# Cloud Build, Cloud Deploy, and Cloud Run for comprehensive application modernization

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.app_name}-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    app_name    = var.app_name
    environment = var.environment
    terraform   = "true"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "migrationcenter.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "run.googleapis.com",
    "container.googleapis.com",
    "sourcerepo.googleapis.com",
    "containeranalysis.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled
resource "time_sleep" "api_enablement" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

# ============================================================================
# MIGRATION CENTER RESOURCES
# ============================================================================

# Migration Center source for legacy application discovery
resource "google_migration_center_source" "legacy_discovery" {
  count = var.migration_center_enabled ? 1 : 0

  location     = var.region
  source_id    = "${var.discovery_source_name}-${local.resource_suffix}"
  display_name = "Legacy Application Discovery - ${var.environment}"
  description  = "Automated discovery source for legacy applications and infrastructure"

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# SOURCE REPOSITORY RESOURCES
# ============================================================================

# Cloud Source Repository for application code
resource "google_sourcerepo_repository" "app_repo" {
  name = "${var.repository_name}-${local.resource_suffix}"

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# IAM RESOURCES
# ============================================================================

# Service account for Cloud Build
resource "google_service_account" "cloud_build_sa" {
  account_id   = "build-sa-${local.resource_suffix}"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations"
}

# Service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "run-sa-${local.resource_suffix}"
  display_name = "Cloud Run Service Account"
  description  = "Service account for Cloud Run service"
}

# Service account for Cloud Deploy
resource "google_service_account" "cloud_deploy_sa" {
  account_id   = "deploy-sa-${local.resource_suffix}"
  display_name = "Cloud Deploy Service Account"
  description  = "Service account for Cloud Deploy operations"
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloud_build_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/run.admin",
    "roles/clouddeploy.operator",
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/source.admin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# IAM bindings for Cloud Run service account
resource "google_project_iam_member" "cloud_run_permissions" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM bindings for Cloud Deploy service account
resource "google_project_iam_member" "cloud_deploy_permissions" {
  for_each = toset([
    "roles/clouddeploy.operator",
    "roles/run.admin",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_deploy_sa.email}"
}

# ============================================================================
# CLOUD BUILD RESOURCES
# ============================================================================

# Cloud Build trigger for automated CI/CD
resource "google_cloudbuild_trigger" "main_trigger" {
  count = var.build_enabled ? 1 : 0

  name        = "main-trigger-${local.resource_suffix}"
  description = "Trigger builds on main branch commits"
  location    = var.region

  source_to_build {
    uri       = google_sourcerepo_repository.app_repo.url
    ref       = "refs/heads/${var.trigger_branch}"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }

  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = google_sourcerepo_repository.app_repo.url
    revision  = "refs/heads/${var.trigger_branch}"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }

  service_account = google_service_account.cloud_build_sa.id

  substitutions = {
    _SERVICE_NAME = var.service_name
    _REGION       = var.region
    _PROJECT_ID   = var.project_id
  }

  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    time_sleep.api_enablement
  ]
}

# ============================================================================
# CLOUD DEPLOY RESOURCES
# ============================================================================

# Cloud Deploy delivery pipeline for multi-environment deployment
resource "google_clouddeploy_delivery_pipeline" "main_pipeline" {
  count = var.deploy_enabled ? 1 : 0

  location = var.region
  name     = "${var.delivery_pipeline_name}-${local.resource_suffix}"

  description = "Delivery pipeline for modernized application deployment"

  project = var.project_id

  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.development[0].name
      profiles  = []
    }

    stages {
      target_id = google_clouddeploy_target.staging[0].name
      profiles  = []
      
      strategy {
        canary {
          canary_deployment {
            percentages = [25, 50, 100]
          }
          runtime_config {
            cloud_run {
              automatic_traffic_control = true
            }
          }
        }
      }
    }

    stages {
      target_id = google_clouddeploy_target.production[0].name
      profiles  = []
      
      strategy {
        canary {
          canary_deployment {
            percentages = [10, 25, 50, 100]
          }
          runtime_config {
            cloud_run {
              automatic_traffic_control = true
            }
          }
        }
      }
    }
  }

  depends_on = [time_sleep.api_enablement]
}

# Cloud Deploy targets for different environments
resource "google_clouddeploy_target" "development" {
  count = var.deploy_enabled ? 1 : 0

  location = var.region
  name     = "development-${local.resource_suffix}"

  description = "Development environment target"
  project     = var.project_id

  run {
    location = "projects/${var.project_id}/locations/${var.region}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.cloud_deploy_sa.email
  }

  depends_on = [time_sleep.api_enablement]
}

resource "google_clouddeploy_target" "staging" {
  count = var.deploy_enabled ? 1 : 0

  location = var.region
  name     = "staging-${local.resource_suffix}"

  description = "Staging environment target"
  project     = var.project_id

  run {
    location = "projects/${var.project_id}/locations/${var.region}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.cloud_deploy_sa.email
  }

  depends_on = [time_sleep.api_enablement]
}

resource "google_clouddeploy_target" "production" {
  count = var.deploy_enabled ? 1 : 0

  location = var.region
  name     = "production-${local.resource_suffix}"

  description = "Production environment target"
  project     = var.project_id

  run {
    location = "projects/${var.project_id}/locations/${var.region}"
  }

  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.cloud_deploy_sa.email
  }

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# CLOUD RUN RESOURCES
# ============================================================================

# Cloud Run service for modernized application
resource "google_cloud_run_v2_service" "modernized_app" {
  name     = "${var.service_name}-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  description = "Modernized application service"

  labels = local.common_labels

  template {
    service_account = var.custom_service_account != "" ? var.custom_service_account : google_service_account.cloud_run_sa.email

    scaling {
      max_instance_count = var.service_max_instances
    }

    containers {
      image = "gcr.io/cloudrun/hello"  # Placeholder image, will be replaced by CI/CD

      resources {
        limits = {
          cpu    = var.service_cpu
          memory = var.service_memory
        }
      }

      ports {
        container_port = 8080
        name          = "http1"
      }

      env {
        name  = "PORT"
        value = "8080"
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      # Health check endpoints
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
    }

    # VPC connector configuration (if enabled)
    dynamic "vpc_access" {
      for_each = var.vpc_connector_enabled ? [1] : []
      content {
        connector = google_vpc_access_connector.connector[0].id
        egress    = "ALL_TRAFFIC"
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_iam_member.cloud_run_permissions,
    time_sleep.api_enablement
  ]
}

# IAM policy for Cloud Run service (allow unauthenticated if specified)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  location = google_cloud_run_v2_service.modernized_app.location
  project  = google_cloud_run_v2_service.modernized_app.project
  service  = google_cloud_run_v2_service.modernized_app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# NETWORKING RESOURCES (Optional)
# ============================================================================

# VPC Connector for private resource access
resource "google_vpc_access_connector" "connector" {
  count = var.vpc_connector_enabled ? 1 : 0

  name          = "vpc-connector-${local.resource_suffix}"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = var.vpc_network_name

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# MONITORING RESOURCES
# ============================================================================

# Monitoring dashboard for application metrics
resource "google_monitoring_dashboard" "app_dashboard" {
  count = var.dashboard_enabled ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Modernized Application Dashboard - ${var.environment}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.modernized_app.name}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Requests per second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Response Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.modernized_app.name}\" AND metric.type=\"run.googleapis.com/request_latencies\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_DELTA"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Latency (ms)"
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
            title = "Instance Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.modernized_app.name}\" AND metric.type=\"run.googleapis.com/container/instance_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "STACKED_AREA"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Instance Count"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [time_sleep.api_enablement]
}

# Alerting policy for high error rate
resource "google_monitoring_alert_policy" "high_error_rate" {
  count = var.alerting_enabled ? 1 : 0

  display_name = "High Error Rate - ${google_cloud_run_v2_service.modernized_app.name}"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.modernized_app.name}\" AND metric.type=\"run.googleapis.com/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_threshold

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = []

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# CONTAINER SECURITY RESOURCES (Optional)
# ============================================================================

# Binary Authorization policy for container security
resource "google_binary_authorization_policy" "policy" {
  count = var.enable_binary_authorization ? 1 : 0

  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.project_id}/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      google_binary_authorization_attestor.attestor[0].name
    ]
  }

  depends_on = [time_sleep.api_enablement]
}

# Binary Authorization attestor
resource "google_binary_authorization_attestor" "attestor" {
  count = var.enable_binary_authorization ? 1 : 0

  name = "build-attestor-${local.resource_suffix}"
  description = "Attestor for build verification"

  attestation_authority_note {
    note_reference = google_container_analysis_note.note[0].name
    public_keys {
      ascii_armored_pgp_public_key = file("${path.module}/attestor.pub")
    }
  }

  depends_on = [time_sleep.api_enablement]
}

# Container Analysis note for attestation
resource "google_container_analysis_note" "note" {
  count = var.enable_binary_authorization ? 1 : 0

  name = "build-note-${local.resource_suffix}"
  
  attestation_authority {
    hint {
      human_readable_name = "Build verification"
    }
  }

  depends_on = [time_sleep.api_enablement]
}

# ============================================================================
# COST MANAGEMENT RESOURCES (Optional)
# ============================================================================

# Budget for cost management
resource "google_billing_budget" "budget" {
  count = var.budget_enabled ? 1 : 0

  billing_account = data.google_billing_account.account[0].id
  display_name    = "Legacy Modernization Budget - ${var.environment}"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    labels = {
      "app_name" = [var.app_name]
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }
}

# Data source for billing account (if budget is enabled)
data "google_billing_account" "account" {
  count = var.budget_enabled ? 1 : 0
  open  = true
}