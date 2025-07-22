# Data Governance Workflows with Dataplex and Cloud Workflows
# This configuration implements an intelligent data governance solution using:
# - Dataplex Universal Catalog for unified data asset management
# - Cloud DLP for sensitive data discovery and classification
# - BigQuery for analytical processing and governance metrics
# - Cloud Workflows for orchestrating end-to-end governance processes
# - Cloud Functions for data quality assessment
# - Cloud Monitoring for governance alerting

# Enable required APIs for data governance services
resource "google_project_service" "dataplex_api" {
  project = var.project_id
  service = "dataplex.googleapis.com"
}

resource "google_project_service" "workflows_api" {
  project = var.project_id
  service = "workflows.googleapis.com"
}

resource "google_project_service" "dlp_api" {
  project = var.project_id
  service = "dlp.googleapis.com"
}

resource "google_project_service" "bigquery_api" {
  project = var.project_id
  service = "bigquery.googleapis.com"
}

resource "google_project_service" "cloudfunctions_api" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
}

resource "google_project_service" "monitoring_api" {
  project = var.project_id
  service = "monitoring.googleapis.com"
}

resource "google_project_service" "logging_api" {
  project = var.project_id
  service = "logging.googleapis.com"
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Service account for data governance operations
resource "google_service_account" "governance_sa" {
  account_id   = "governance-sa-${random_string.suffix.result}"
  display_name = "Data Governance Service Account"
  description  = "Service account for data governance workflows and operations"
  project      = var.project_id
}

# IAM roles for governance service account
resource "google_project_iam_member" "governance_sa_dataplex_admin" {
  project = var.project_id
  role    = "roles/dataplex.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

resource "google_project_iam_member" "governance_sa_dlp_admin" {
  project = var.project_id
  role    = "roles/dlp.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

resource "google_project_iam_member" "governance_sa_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

resource "google_project_iam_member" "governance_sa_workflows_admin" {
  project = var.project_id
  role    = "roles/workflows.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

resource "google_project_iam_member" "governance_sa_cloudfunctions_admin" {
  project = var.project_id
  role    = "roles/cloudfunctions.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

resource "google_project_iam_member" "governance_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
}

# Cloud Storage bucket for data lake
resource "google_storage_bucket" "data_lake" {
  name          = "governance-data-lake-${random_string.suffix.result}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true

  # Enable encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.governance_key.id
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    team        = "data-engineering"
  }

  depends_on = [google_project_service.dataplex_api]
}

# KMS key for encryption
resource "google_kms_key_ring" "governance_keyring" {
  name     = "governance-keyring-${random_string.suffix.result}"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "governance_key" {
  name     = "governance-key"
  key_ring = google_kms_key_ring.governance_keyring.id
  purpose  = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }
}

# IAM binding for KMS key
resource "google_kms_crypto_key_iam_binding" "governance_key_binding" {
  crypto_key_id = google_kms_crypto_key.governance_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.governance_sa.email}",
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# Get project details
data "google_project" "project" {
  project_id = var.project_id
}

# BigQuery dataset for governance analytics
resource "google_bigquery_dataset" "governance_analytics" {
  dataset_id    = "governance_analytics_${random_string.suffix.result}"
  friendly_name = "Data Governance Analytics"
  description   = "Dataset for storing governance metrics, compliance reports, and audit logs"
  location      = var.region
  project       = var.project_id

  # Enable encryption
  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.governance_key.id
  }

  # Access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.governance_sa.email
  }

  access {
    role   = "READER"
    domain = var.organization_domain
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    team        = "data-engineering"
  }

  depends_on = [google_project_service.bigquery_api]
}

# BigQuery table for data quality metrics
resource "google_bigquery_table" "data_quality_metrics" {
  dataset_id = google_bigquery_dataset.governance_analytics.dataset_id
  table_id   = "data_quality_metrics"
  project    = var.project_id

  description = "Table for storing data quality assessment results and metrics"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "asset_name"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "zone"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "quality_score"
      type = "FLOAT64"
      mode = "REQUIRED"
    },
    {
      name = "issues_found"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "scan_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "details"
      type = "JSON"
      mode = "NULLABLE"
    }
  ])

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["zone", "asset_name"]

  labels = {
    environment = var.environment
    purpose     = "data-governance"
  }
}

# BigQuery table for compliance reports
resource "google_bigquery_table" "compliance_reports" {
  dataset_id = google_bigquery_dataset.governance_analytics.dataset_id
  table_id   = "compliance_reports"
  project    = var.project_id

  description = "Table for storing compliance monitoring results and violations"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "asset_name"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "compliance_status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "violations"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "sensitive_data_types"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "risk_level"
      type = "STRING"
      mode = "REQUIRED"
    }
  ])

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["compliance_status", "risk_level"]

  labels = {
    environment = var.environment
    purpose     = "data-governance"
  }
}

# BigQuery table for governance audit log
resource "google_bigquery_table" "governance_audit_log" {
  dataset_id = google_bigquery_dataset.governance_analytics.dataset_id
  table_id   = "governance_audit_log"
  project    = var.project_id

  description = "Table for storing governance workflow execution audit logs"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "action"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "user"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "asset"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "zone"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "details"
      type = "JSON"
      mode = "NULLABLE"
    }
  ])

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["action", "status"]

  labels = {
    environment = var.environment
    purpose     = "data-governance"
  }
}

# Dataplex Lake for unified data management
resource "google_dataplex_lake" "governance_lake" {
  name        = "governance-lake-${random_string.suffix.result}"
  location    = var.region
  project     = var.project_id
  description = "Intelligent data governance lake for unified asset management"

  metastore {
    service = var.metastore_service_id
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    team        = "data-engineering"
  }

  depends_on = [google_project_service.dataplex_api]
}

# Raw data zone for ingestion
resource "google_dataplex_zone" "raw_data_zone" {
  name         = "raw-data-zone"
  location     = var.region
  lake         = google_dataplex_lake.governance_lake.name
  project      = var.project_id
  type         = "RAW"
  description  = "Raw data zone for data ingestion and initial processing"

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  discovery_spec {
    enabled = true
    schedule = "0 */6 * * *"  # Every 6 hours
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    zone_type   = "raw"
  }
}

# Curated data zone for processed analytics
resource "google_dataplex_zone" "curated_data_zone" {
  name         = "curated-data-zone"
  location     = var.region
  lake         = google_dataplex_lake.governance_lake.name
  project      = var.project_id
  type         = "CURATED"
  description  = "Curated data zone for processed analytics and reporting"

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  discovery_spec {
    enabled = true
    schedule = "0 */12 * * *"  # Every 12 hours
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    zone_type   = "curated"
  }
}

# Dataplex asset for Cloud Storage bucket
resource "google_dataplex_asset" "storage_asset" {
  name         = "storage-asset-${random_string.suffix.result}"
  location     = var.region
  lake         = google_dataplex_lake.governance_lake.name
  dataplex_zone = google_dataplex_zone.raw_data_zone.name
  project      = var.project_id
  description  = "Storage asset for data lake governance"

  resource_spec {
    name = google_storage_bucket.data_lake.name
    type = "STORAGE_BUCKET"
  }

  discovery_spec {
    enabled = true
    schedule = "0 */6 * * *"
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    asset_type  = "storage"
  }
}

# Dataplex asset for BigQuery dataset
resource "google_dataplex_asset" "bigquery_asset" {
  name         = "bigquery-asset-${random_string.suffix.result}"
  location     = var.region
  lake         = google_dataplex_lake.governance_lake.name
  dataplex_zone = google_dataplex_zone.curated_data_zone.name
  project      = var.project_id
  description  = "BigQuery asset for analytics governance"

  resource_spec {
    name = "projects/${var.project_id}/datasets/${google_bigquery_dataset.governance_analytics.dataset_id}"
    type = "BIGQUERY_DATASET"
  }

  discovery_spec {
    enabled = true
    schedule = "0 */12 * * *"
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
    asset_type  = "bigquery"
  }
}

# Cloud DLP inspection template for sensitive data detection
resource "google_data_loss_prevention_inspect_template" "governance_template" {
  parent       = "projects/${var.project_id}"
  description  = "Template for detecting sensitive data in governance workflows"
  display_name = "Governance Data Inspection Template"

  inspect_config {
    info_types {
      name = "EMAIL_ADDRESS"
    }
    info_types {
      name = "PHONE_NUMBER"
    }
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }
    info_types {
      name = "US_SOCIAL_SECURITY_NUMBER"
    }
    info_types {
      name = "PERSON_NAME"
    }

    min_likelihood = "POSSIBLE"
    include_quote  = true

    limits {
      max_findings_per_request = 1000
    }
  }

  depends_on = [google_project_service.dlp_api]
}

# Cloud DLP job trigger for automated scanning
resource "google_data_loss_prevention_job_trigger" "governance_trigger" {
  parent       = "projects/${var.project_id}"
  description  = "Automated trigger for scanning data lake assets"
  display_name = "Governance Automated Scan Trigger"

  triggers {
    schedule {
      recurrence_period_duration = "604800s"  # Weekly
    }
  }

  inspect_job {
    inspect_template_name = google_data_loss_prevention_inspect_template.governance_template.name
    
    storage_config {
      cloud_storage_options {
        file_set {
          url = "${google_storage_bucket.data_lake.url}/*"
        }
        bytes_limit_per_file = 1048576  # 1MB
      }
    }
  }

  depends_on = [google_project_service.dlp_api]
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      dataset_name = google_bigquery_dataset.governance_analytics.dataset_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source
resource "google_storage_bucket" "function_source_bucket" {
  name          = "governance-function-source-${random_string.suffix.result}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    purpose     = "function-source"
  }
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_string.suffix.result}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for data quality assessment
resource "google_cloudfunctions_function" "data_quality_assessor" {
  name        = "data-quality-assessor-${random_string.suffix.result}"
  location    = var.region
  project     = var.project_id
  description = "Function for automated data quality assessment"

  runtime             = "python311"
  available_memory_mb = 512
  timeout             = 300
  entry_point         = "assess_data_quality"

  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  service_account_email = google_service_account.governance_sa.email

  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = google_bigquery_dataset.governance_analytics.dataset_id
  }

  labels = {
    environment = var.environment
    purpose     = "data-governance"
  }

  depends_on = [google_project_service.cloudfunctions_api]
}

# Cloud Workflows for governance orchestration
resource "google_workflows_workflow" "governance_workflow" {
  name        = "intelligent-governance-workflow-${random_string.suffix.result}"
  region      = var.region
  project     = var.project_id
  description = "Intelligent data governance orchestration workflow"

  source_contents = templatefile("${path.module}/workflow_source/governance-workflow.yaml", {
    project_id     = var.project_id
    region         = var.region
    function_name  = google_cloudfunctions_function.data_quality_assessor.name
  })

  service_account = google_service_account.governance_sa.email

  labels = {
    environment = var.environment
    purpose     = "data-governance"
  }

  depends_on = [google_project_service.workflows_api]
}

# Cloud Monitoring alert policy for data quality issues
resource "google_monitoring_alert_policy" "data_quality_alert" {
  display_name = "Data Quality Alert Policy"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Low Data Quality Score"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.data_quality_assessor.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = var.notification_channels

  documentation {
    content = "Alert triggered when data quality scores drop below acceptable threshold"
  }

  enabled = true

  depends_on = [google_project_service.monitoring_api]
}

# Log-based metric for governance workflow executions
resource "google_logging_metric" "governance_workflow_executions" {
  name    = "governance_workflow_executions"
  project = var.project_id

  filter = "resource.type=\"workflows.googleapis.com/Workflow\" AND jsonPayload.workflow_name=\"${google_workflows_workflow.governance_workflow.name}\""

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Governance Workflow Executions"
  }

  depends_on = [google_project_service.logging_api]
}

# Sample data insertion for testing
resource "null_resource" "sample_data_insertion" {
  triggers = {
    table_created = google_bigquery_table.data_quality_metrics.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud auth application-default login --quiet || true
      bq query --use_legacy_sql=false --project_id=${var.project_id} \
      "INSERT INTO \`${var.project_id}.${google_bigquery_dataset.governance_analytics.dataset_id}.data_quality_metrics\`
      (timestamp, asset_name, zone, quality_score, issues_found, scan_type, details)
      VALUES
      (CURRENT_TIMESTAMP(), 'sample-dataset', 'raw-data-zone', 0.95, 2, 'automated', JSON '{\"completeness\": 0.98, \"validity\": 0.92}');"
    EOT
  }

  depends_on = [google_bigquery_table.data_quality_metrics]
}