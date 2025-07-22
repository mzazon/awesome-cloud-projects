# Main Terraform configuration for GCP Database Development Workflow
# This configuration creates a complete development environment with Cloud Workstations,
# AlloyDB Omni support, Cloud Build, and Cloud Source Repositories

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Unique identifier for this deployment
  deployment_id = random_id.suffix.hex

  # Common resource naming convention
  name_prefix = "${var.resource_prefix}-${var.environment}-${local.deployment_id}"

  # Common labels applied to all resources
  common_labels = merge(
    {
      environment    = var.environment
      project       = "database-development"
      managed-by    = "terraform"
      deployment-id = local.deployment_id
      recipe-name   = "database-development-alloydb-omni-workstations"
    },
    var.additional_labels
  )
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "workstations.googleapis.com",
    "compute.googleapis.com",
    "sourcerepo.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "pubsub.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent deletion of essential services
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# VPC Network for Cloud Workstations
module "vpc_network" {
  source  = "terraform-google-modules/network/google"
  version = "~> 11.1"

  project_id   = var.project_id
  network_name = "${local.name_prefix}-vpc"
  description  = "VPC network for database development workstations"

  # Use custom subnets for better control
  subnets = [
    {
      subnet_name               = "${local.name_prefix}-workstations-subnet"
      subnet_ip                 = var.workstation_subnet_cidr
      subnet_region            = var.region
      subnet_private_access     = var.security_config.enable_private_google_access
      subnet_flow_logs         = var.monitoring_config.enable_flow_logs
      subnet_flow_logs_interval = "INTERVAL_5_SEC"
      subnet_flow_logs_sampling = 0.5
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      description              = "Subnet for Cloud Workstations instances"
    }
  ]

  # Firewall rules for workstation communication
  firewall_rules = [
    {
      name               = "${local.name_prefix}-allow-workstation-internal"
      description        = "Allow internal communication between workstations"
      direction          = "INGRESS"
      priority           = 1000
      ranges             = [var.workstation_subnet_cidr, "10.0.0.0/8"]
      source_tags        = null
      source_service_accounts = null
      target_tags        = ["workstation"]
      target_service_accounts = null
      allow = [
        {
          protocol = "tcp"
          ports    = ["22", "80", "443", "1024-65535"]
        },
        {
          protocol = "udp"
          ports    = ["53", "1024-65535"]
        },
        {
          protocol = "icmp"
          ports    = null
        }
      ]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name               = "${local.name_prefix}-allow-google-apis"
      description        = "Allow access to Google Cloud APIs"
      direction          = "EGRESS"
      priority           = 1000
      ranges             = ["199.36.153.8/30"]  # Google APIs
      source_tags        = null
      source_service_accounts = null
      target_tags        = ["workstation"]
      target_service_accounts = null
      allow = [
        {
          protocol = "tcp"
          ports    = ["443"]
        }
      ]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
  ]

  # Apply common labels
  module_depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Workstations
resource "google_service_account" "workstation_sa" {
  account_id   = "${local.name_prefix}-workstation-sa"
  display_name = "Cloud Workstations Service Account"
  description  = "Service account for Cloud Workstations instances in database development environment"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for workstation service account
resource "google_project_iam_member" "workstation_sa_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/source.reader",
    "roles/cloudbuild.builds.viewer",
    "roles/storage.objectViewer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"

  depends_on = [google_service_account.workstation_sa]
}

# Service Account for Cloud Build
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "${local.name_prefix}-cloudbuild-sa"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations in database development workflow"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/source.reader",
    "roles/storage.admin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"

  depends_on = [google_service_account.cloudbuild_sa]
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "container_images" {
  repository_id = "${local.name_prefix}-containers"
  format        = var.artifact_registry_config.format
  location      = var.region
  description   = "Container repository for database development workstation images"

  labels = local.common_labels

  # Cleanup policies for cost optimization
  dynamic "cleanup_policies" {
    for_each = var.artifact_registry_config.cleanup_policy_enabled ? [1] : []
    content {
      id     = "delete-untagged"
      action = "DELETE"
      condition {
        tag_state  = var.artifact_registry_config.cleanup_delete_untagged ? "UNTAGGED" : "ANY"
        older_than = "7d"
      }
    }
  }

  dynamic "cleanup_policies" {
    for_each = var.artifact_registry_config.cleanup_policy_enabled ? [1] : []
    content {
      id     = "keep-tagged-versions"
      action = "KEEP"
      most_recent_versions {
        keep_count = var.artifact_registry_config.cleanup_keep_tag_revisions
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Source Repository
resource "google_sourcerepo_repository" "database_development" {
  name    = "${local.name_prefix}-${var.repository_name}"
  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for repository developers
resource "google_sourcerepo_repository_iam_member" "repository_developers" {
  for_each = toset(var.repository_developers)

  project    = var.project_id
  repository = google_sourcerepo_repository.database_development.name
  role       = "roles/source.developer"
  member     = "user:${each.value}"

  depends_on = [google_sourcerepo_repository.database_development]
}

# Pub/Sub topic for build notifications
resource "google_pubsub_topic" "build_notifications" {
  name    = "${local.name_prefix}-build-notifications"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Build trigger for main branch
resource "google_cloudbuild_trigger" "database_testing" {
  name        = "${local.name_prefix}-database-testing"
  description = "Automated database testing trigger for main branch changes"
  location    = var.region
  project     = var.project_id

  # Trigger configuration
  repository_event_config {
    repository = google_sourcerepo_repository.database_development.id
    push {
      branch = var.build_trigger_config.branch_pattern
    }
  }

  # Build configuration inline
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["build", "-t", "alloydb-omni-test", "-f", "alloydb-config/Dockerfile", "."]
    }

    step {
      name       = "docker/compose"
      entrypoint = "docker-compose"
      args       = ["-f", "alloydb-config/docker-compose.yml", "up", "-d"]
      env        = ["COMPOSE_PROJECT_NAME=test-db-${random_id.suffix.hex}"]
    }

    step {
      name = "postgres:15"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOF
        apt-get update && apt-get install -y postgresql-client
        until pg_isready -h alloydb-dev -p 5432 -U dev_user; do
          echo "Waiting for database..."
          sleep 5
        done
        echo "Database is ready"
        EOF
      ]
    }

    step {
      name = "postgres:15"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOF
        apt-get update && apt-get install -y postgresql-client
        for file in migrations/*.sql; do
          if [ -f "$file" ]; then
            echo "Running migration: $file"
            PGPASSWORD=dev_password_123 psql -h alloydb-dev -U dev_user -d development_db -f "$file"
          fi
        done
        EOF
      ]
    }

    step {
      name = "postgres:15"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOF
        apt-get update && apt-get install -y postgresql-client
        for file in tests/*.sql; do
          if [ -f "$file" ]; then
            echo "Running test: $file"
            PGPASSWORD=dev_password_123 psql -h alloydb-dev -U dev_user -d development_db -f "$file"
          fi
        done
        EOF
      ]
    }

    step {
      name       = "docker/compose"
      entrypoint = "docker-compose"
      args       = ["-f", "alloydb-config/docker-compose.yml", "down", "-v"]
      env        = ["COMPOSE_PROJECT_NAME=test-db-${random_id.suffix.hex}"]
    }

    options {
      logging           = var.build_trigger_config.include_build_logs ? "CLOUD_LOGGING_ONLY" : "LEGACY"
      machine_type      = "E2_HIGHCPU_8"
      disk_size_gb      = 100
      substitution_option = "ALLOW_LOOSE"
    }

    timeout = "${var.build_trigger_config.timeout_seconds}s"

    # Service account for builds
    service_account = google_service_account.cloudbuild_sa.id
  }

  # Substitutions for build variables
  substitutions = {
    _ARTIFACT_REGISTRY_REPO = google_artifact_registry_repository.container_images.name
    _REGION                 = var.region
    _PROJECT_ID            = var.project_id
  }

  depends_on = [
    google_service_account.cloudbuild_sa,
    google_sourcerepo_repository.database_development,
    google_artifact_registry_repository.container_images
  ]
}

# Cloud Workstations Cluster
resource "google_workstations_workstation_cluster" "database_development" {
  provider                    = google-beta
  workstation_cluster_id      = "${local.name_prefix}-cluster"
  location                   = var.region
  project                    = var.project_id
  display_name               = "Database Development Cluster"

  # Network configuration
  network    = module.vpc_network.network_self_link
  subnetwork = module.vpc_network.subnets_self_links[0]

  # Security configuration
  private_cluster_config {
    enable_private_endpoint = var.security_config.enable_private_google_access
    cluster_hostname       = "${local.name_prefix}-cluster.${var.region}.workstations.googleusercontent.com"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    module.vpc_network
  ]
}

# Cloud Workstations Configuration
resource "google_workstations_workstation_config" "database_development" {
  provider               = google-beta
  workstation_config_id  = "${local.name_prefix}-config"
  workstation_cluster_id = google_workstations_workstation_cluster.database_development.workstation_cluster_id
  location              = var.region
  project               = var.project_id
  display_name          = "Database Development Environment"

  # Host configuration
  host {
    gce_instance {
      machine_type                = var.workstation_cluster_config.machine_type
      boot_disk_size_gb          = var.workstation_cluster_config.boot_disk_size_gb
      disable_public_ip_addresses = var.workstation_cluster_config.disable_public_ip_addresses
      enable_nested_virtualization = var.workstation_cluster_config.enable_nested_virtualization
      service_account            = google_service_account.workstation_sa.email

      # Security configurations
      shielded_instance_config {
        enable_secure_boot          = var.security_config.enable_secure_boot
        enable_vtpm                = true
        enable_integrity_monitoring = var.security_config.enable_integrity_monitoring
      }

      # Network tags for firewall rules
      tags = ["workstation", "database-development"]
    }
  }

  # Container configuration
  container {
    image = var.workstation_container_image
    env = {
      "DEBIAN_FRONTEND" = "noninteractive"
      "DEVELOPMENT_ENV" = "alloydb-omni"
    }
    run_as_user = 1000
  }

  # Persistent storage
  persistent_directories {
    mount_path = "/home/user"
    gce_persistent_disk {
      size_gb   = var.workstation_cluster_config.persistent_disk_size_gb
      disk_type = "pd-standard"
    }
  }

  # Timeouts
  idle_timeout    = var.workstation_cluster_config.idle_timeout
  running_timeout = var.workstation_cluster_config.running_timeout

  # Enable audit logging if configured
  dynamic "enable_audit_agent" {
    for_each = var.workstation_cluster_config.enable_audit_agent ? [1] : []
    content {
      # Audit agent configuration would go here
    }
  }

  labels = local.common_labels

  depends_on = [
    google_workstations_workstation_cluster.database_development,
    google_service_account.workstation_sa
  ]
}

# IAM bindings for workstation users
resource "google_workstations_workstation_config_iam_member" "workstation_users" {
  provider = google-beta
  for_each = toset(var.workstation_users)

  project                = var.project_id
  location              = var.region
  workstation_cluster_id = google_workstations_workstation_cluster.database_development.workstation_cluster_id
  workstation_config_id  = google_workstations_workstation_config.database_development.workstation_config_id
  role                  = "roles/workstations.user"
  member                = "user:${each.value}"

  depends_on = [google_workstations_workstation_config.database_development]
}

# Sample workstation instance (can be replicated)
resource "google_workstations_workstation" "sample_workstation" {
  provider = google-beta
  
  workstation_id         = "${local.name_prefix}-sample-workstation"
  workstation_config_id  = google_workstations_workstation_config.database_development.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.database_development.workstation_cluster_id
  location              = var.region
  project               = var.project_id
  display_name          = "Sample Database Development Workstation"

  labels = merge(local.common_labels, {
    workstation-type = "sample"
    developer       = "sample-user"
  })

  depends_on = [google_workstations_workstation_config.database_development]
}

# Cloud Monitoring Notification Channel (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.monitoring_config.notification_email != "" ? 1 : 0

  display_name = "Database Development Team"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.monitoring_config.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Log sink for workstation logs (if enabled)
resource "google_logging_project_sink" "workstation_logs" {
  count = var.monitoring_config.enable_workstation_logs ? 1 : 0

  name        = "${local.name_prefix}-workstation-logs"
  description = "Log sink for Cloud Workstations in database development environment"
  project     = var.project_id

  # Send logs to Cloud Logging
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${local.name_prefix}-workstation-sink"

  # Filter for workstation-related logs
  filter = <<-EOF
    resource.type="gce_instance"
    resource.labels.instance_name=~"${local.name_prefix}-.*"
    OR
    resource.type="workstation"
    resource.labels.workstation_cluster_name="${google_workstations_workstation_cluster.database_development.workstation_cluster_id}"
  EOF

  # Retention configuration
  exclusions {
    name        = "exclude-debug-logs"
    description = "Exclude debug level logs to reduce volume"
    filter      = "severity<=DEBUG"
  }

  depends_on = [
    google_project_service.required_apis,
    google_workstations_workstation_cluster.database_development
  ]
}

# Wait for all APIs to be enabled before creating dependent resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}