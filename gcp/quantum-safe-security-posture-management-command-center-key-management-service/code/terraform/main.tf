# ============================================================================
# Quantum-Safe Security Posture Management with Security Command Center and Cloud KMS
# ============================================================================
# This Terraform configuration deploys a comprehensive quantum-safe security
# posture management solution using Google Cloud Security Command Center,
# Cloud KMS with post-quantum cryptography, and automated compliance monitoring.

# Create project for quantum security implementation
resource "google_project" "quantum_security" {
  name            = "Quantum Security Posture Management"
  project_id      = var.project_id
  org_id          = var.organization_id
  billing_account = var.billing_account

  # Auto-delete project after testing (remove for production)
  lifecycle {
    prevent_destroy = true
  }
}

# Link billing account to the project
resource "google_billing_project_info" "quantum_security_billing" {
  project         = google_project.quantum_security.project_id
  billing_account = var.billing_account
}

# Enable required APIs for quantum security infrastructure
resource "google_project_service" "required_apis" {
  for_each = toset([
    "securitycenter.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudasset.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "orgpolicy.googleapis.com"
  ])

  project = google_project.quantum_security.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = true

  depends_on = [google_billing_project_info.quantum_security_billing]
}

# ============================================================================
# Quantum-Safe Key Management Infrastructure
# ============================================================================

# Create KMS keyring for post-quantum cryptography
resource "google_kms_key_ring" "quantum_keyring" {
  name     = var.kms_keyring_name
  location = var.region
  project  = google_project.quantum_security.project_id

  depends_on = [google_project_service.required_apis]
}

# Post-quantum ML-DSA-65 key for lattice-based digital signatures
resource "google_kms_crypto_key" "ml_dsa_key" {
  name            = "${var.kms_key_name}-ml-dsa"
  key_ring        = google_kms_key_ring.quantum_keyring.id
  purpose         = "ASYMMETRIC_SIGN"
  rotation_period = var.kms_key_rotation_period

  version_template {
    algorithm = var.pq_algorithms.ml_dsa
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Post-quantum SLH-DSA key for hash-based digital signatures
resource "google_kms_crypto_key" "slh_dsa_key" {
  name            = "${var.kms_key_name}-slh-dsa"
  key_ring        = google_kms_key_ring.quantum_keyring.id
  purpose         = "ASYMMETRIC_SIGN"
  rotation_period = var.kms_key_rotation_period

  version_template {
    algorithm = var.pq_algorithms.slh_dsa
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Service account for quantum security automation
resource "google_service_account" "quantum_security_automation" {
  account_id   = "quantum-security-automation"
  display_name = "Quantum Security Automation Service Account"
  description  = "Service account for automated quantum security operations and compliance reporting"
  project      = google_project.quantum_security.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM binding for KMS keyring access
resource "google_kms_key_ring_iam_binding" "quantum_keyring_access" {
  key_ring_id = google_kms_key_ring.quantum_keyring.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.quantum_security_automation.email}",
  ]
}

# Additional IAM roles for comprehensive quantum security operations
resource "google_project_iam_member" "quantum_security_roles" {
  for_each = toset([
    "roles/securitycenter.admin",
    "roles/cloudasset.viewer",
    "roles/monitoring.editor",
    "roles/logging.viewer",
    "roles/pubsub.editor",
    "roles/storage.admin",
    "roles/cloudfunctions.developer",
    "roles/cloudscheduler.admin"
  ])

  project = google_project.quantum_security.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.quantum_security_automation.email}"
}

# ============================================================================
# Asset Inventory and Change Tracking
# ============================================================================

# Pub/Sub topic for cryptographic asset change notifications
resource "google_pubsub_topic" "crypto_asset_changes" {
  name    = "crypto-asset-changes"
  project = google_project.quantum_security.project_id

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for processing asset changes
resource "google_pubsub_subscription" "crypto_asset_subscription" {
  name    = "crypto-asset-subscription"
  topic   = google_pubsub_topic.crypto_asset_changes.name
  project = google_project.quantum_security.project_id

  # Message retention for 7 days
  message_retention_duration = "604800s"
  retain_acked_messages      = false

  # Enable dead letter topic for failed processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.crypto_asset_dead_letter.id
    max_delivery_attempts = 5
  }

  ack_deadline_seconds = 20
}

# Dead letter topic for failed asset change processing
resource "google_pubsub_topic" "crypto_asset_dead_letter" {
  name    = "crypto-asset-dead-letter"
  project = google_project.quantum_security.project_id

  depends_on = [google_project_service.required_apis]
}

# Cloud Asset Inventory feed for cryptographic resources
resource "google_cloud_asset_organization_feed" "crypto_assets_feed" {
  billing_project = google_project.quantum_security.project_id
  org_id          = var.organization_id
  feed_id         = "quantum-crypto-assets"
  content_type    = "RESOURCE"

  asset_types = var.asset_types_to_track

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.crypto_asset_changes.id
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.crypto_asset_changes
  ]
}

# ============================================================================
# Storage for Asset Inventory and Compliance Reports
# ============================================================================

# Storage bucket for cryptographic asset inventory exports
resource "google_storage_bucket" "crypto_inventory" {
  name          = "${var.project_id}-crypto-inventory"
  location      = var.region
  project       = google_project.quantum_security.project_id
  force_destroy = true

  # Enable versioning for audit trail
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
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
      type = "Delete"
    }
  }

  # Enable encryption with Google-managed keys
  encryption {
    default_kms_key_name = google_kms_crypto_key.ml_dsa_key.id
  }

  depends_on = [google_project_service.required_apis]
}

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-function-source"
  location      = var.region
  project       = google_project.quantum_security.project_id
  force_destroy = true

  depends_on = [google_project_service.required_apis]
}

# IAM binding for storage bucket access
resource "google_storage_bucket_iam_binding" "crypto_inventory_access" {
  bucket = google_storage_bucket.crypto_inventory.name
  role   = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.quantum_security_automation.email}",
  ]
}

# ============================================================================
# Cloud Functions for Compliance Reporting
# ============================================================================

# Create compliance reporting function source code
resource "google_storage_bucket_object" "compliance_function_zip" {
  name   = "compliance-function-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}.zip"
  bucket = google_storage_bucket.function_source.name

  # Create a simple zip file with the Python function
  source = data.archive_file.compliance_function.output_path

  depends_on = [google_storage_bucket.function_source]
}

# Archive the compliance function source code
data "archive_file" "compliance_function" {
  type        = "zip"
  output_path = "/tmp/compliance-function.zip"

  source {
    content = templatefile("${path.module}/function_code/compliance_report.py", {
      organization_id = var.organization_id
      project_id      = var.project_id
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Function for automated compliance reporting
resource "google_cloudfunctions_function" "quantum_compliance_report" {
  name        = "quantum-compliance-report"
  description = "Generate automated quantum readiness compliance reports"
  runtime     = "python39"
  project     = google_project.quantum_security.project_id
  region      = var.region

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.compliance_function_zip.name
  entry_point          = "generate_quantum_compliance_report"

  https_trigger {}

  environment_variables = {
    ORGANIZATION_ID = var.organization_id
    PROJECT_ID      = var.project_id
    BUCKET_NAME     = google_storage_bucket.crypto_inventory.name
  }

  service_account_email = google_service_account.quantum_security_automation.email

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.compliance_function_zip
  ]
}

# ============================================================================
# Cloud Scheduler for Automated Reporting
# ============================================================================

# Scheduled job for quarterly compliance reports
resource "google_cloud_scheduler_job" "quantum_compliance_scheduler" {
  name      = "quantum-compliance-scheduler"
  project   = google_project.quantum_security.project_id
  region    = var.region
  schedule  = var.compliance_schedule
  time_zone = "UTC"

  description = "Automated quarterly quantum readiness compliance reporting"

  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.quantum_compliance_report.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.quantum_security_automation.email
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.quantum_compliance_report
  ]
}

# ============================================================================
# Cloud Monitoring Dashboard and Alerts
# ============================================================================

# Notification channel for quantum security alerts
resource "google_monitoring_notification_channel" "security_alerts" {
  display_name = "Quantum Security Alerts"
  type         = "email"
  project      = google_project.quantum_security.project_id

  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Monitoring dashboard for quantum security posture
resource "google_monitoring_dashboard" "quantum_security_dashboard" {
  project        = google_project.quantum_security.project_id
  dashboard_json = jsonencode({
    displayName = "Quantum Security Posture Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Post-Quantum Key Usage"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloudkms_cryptokey\" AND resource.labels.key_ring_id=\"${google_kms_key_ring.quantum_keyring.name}\""
                  aggregation = {
                    alignmentPeriod     = "300s"
                    perSeriesAligner    = "ALIGN_COUNT"
                    crossSeriesReducer  = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_BAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Quantum Vulnerability Alerts"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND log_name=\"projects/${google_project.quantum_security.project_id}/logs/quantum_vulnerability_scan\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_COUNT"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Cryptographic Asset Inventory"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudkms_cryptokey\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_COUNT"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.label.algorithm"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Key Count"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Alert policy for quantum vulnerability detection
resource "google_monitoring_alert_policy" "quantum_vulnerability_alerts" {
  display_name = "Quantum Vulnerability Detection"
  project      = google_project.quantum_security.project_id

  conditions {
    display_name = "Weak encryption algorithms detected"
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND log_name=\"projects/${google_project.quantum_security.project_id}/logs/quantum_vulnerability_scan\""
      comparison     = "COMPARISON_GT"
      threshold_value = 0
      duration       = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = [google_monitoring_notification_channel.security_alerts.name]

  documentation {
    content   = "Alert triggered when quantum-vulnerable encryption algorithms are detected in the environment. Immediate assessment and remediation required."
    mime_type = "text/markdown"
  }

  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.security_alerts
  ]
}

# Alert policy for KMS key rotation compliance
resource "google_monitoring_alert_policy" "key_rotation_compliance" {
  display_name = "KMS Key Rotation Compliance"
  project      = google_project.quantum_security.project_id

  conditions {
    display_name = "Post-quantum key rotation overdue"
    condition_threshold {
      filter         = "resource.type=\"cloudkms_cryptokey\" AND resource.labels.key_ring_id=\"${google_kms_key_ring.quantum_keyring.name}\""
      comparison     = "COMPARISON_GT"
      threshold_value = 35 # Days since last rotation
      duration       = "3600s"

      aggregations {
        alignment_period   = "3600s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  alert_strategy {
    auto_close = "172800s" # 48 hours
  }

  notification_channels = [google_monitoring_notification_channel.security_alerts.name]

  documentation {
    content   = "Post-quantum cryptographic keys require rotation for cryptographic agility. Ensure automated rotation is functioning properly."
    mime_type = "text/markdown"
  }

  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.security_alerts
  ]
}

# ============================================================================
# Organization Policies for Quantum Security
# ============================================================================

# Organization policy to require OS Login
resource "google_org_policy_policy" "require_os_login" {
  count = var.enforce_os_login ? 1 : 0

  name   = "organizations/${var.organization_id}/policies/compute.requireOsLogin"
  parent = "organizations/${var.organization_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Organization policy to disable service account key creation
resource "google_org_policy_policy" "disable_service_account_keys" {
  count = var.disable_service_account_keys ? 1 : 0

  name   = "organizations/${var.organization_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "organizations/${var.organization_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Organization policy to restrict crypto key algorithms to quantum-safe only
resource "google_org_policy_policy" "restrict_crypto_algorithms" {
  name   = "organizations/${var.organization_id}/policies/cloudkms.restrictCryptoKeyAlgorithms"
  parent = "organizations/${var.organization_id}"

  spec {
    rules {
      values {
        allowed_values = [
          var.pq_algorithms.ml_dsa,
          var.pq_algorithms.slh_dsa,
          "GOOGLE_SYMMETRIC_ENCRYPTION" # Allow symmetric encryption
        ]
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}