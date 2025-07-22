# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Main Terraform configuration for Data Quality Monitoring with Dataform and Cloud Scheduler
# This file creates a complete data quality monitoring solution using Google Cloud services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  dataset_id           = "${var.dataset_name}_${random_id.suffix.hex}"
  assertion_dataset_id = "${var.assertion_dataset_name}_${random_id.suffix.hex}"
  scheduler_job_id     = "${var.scheduler_job_name}-${random_id.suffix.hex}"
  service_account_id   = "${var.service_account_name}-${random_id.suffix.hex}"

  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "data-quality-monitoring"
    recipe-id   = "f8a3b2c1"
  })

  # Required Google Cloud APIs for the solution
  required_apis = [
    "dataform.googleapis.com",
    "cloudscheduler.googleapis.com", 
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []

  project = var.project_id
  service = each.value

  # Prevent disabling APIs when Terraform is destroyed
  disable_on_destroy = false

  # Allow some time for API enablement
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Scheduler and Dataform operations
resource "google_service_account" "dataform_scheduler" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Service account for automated data quality monitoring with Dataform and Cloud Scheduler"

  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "dataform_editor" {
  project = var.project_id
  role    = "roles/dataform.editor"
  member  = "serviceAccount:${google_service_account.dataform_scheduler.email}"
}

resource "google_project_iam_member" "bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.dataform_scheduler.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.dataform_scheduler.email}"
}

# Create BigQuery dataset for sample data
resource "google_bigquery_dataset" "sample_dataset" {
  project       = var.project_id
  dataset_id    = local.dataset_id
  friendly_name = "Sample E-commerce Data for Quality Monitoring"
  description   = "Dataset containing sample e-commerce data with intentional quality issues for testing data quality assertions"
  location      = var.dataset_location

  # Configure access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.dataform_scheduler.email
  }

  access {
    role         = "READER"
    special_group = "projectReaders"
  }

  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }

  access {
    role         = "OWNER"
    special_group = "projectOwners"
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]

  # Prevent accidental deletion in production
  deletion_protection = var.deletion_protection
}

# Create BigQuery dataset for Dataform assertions
resource "google_bigquery_dataset" "assertion_dataset" {
  project       = var.project_id
  dataset_id    = local.assertion_dataset_id
  friendly_name = "Dataform Data Quality Assertions"
  description   = "Dataset containing data quality assertion results and monitoring views"
  location      = var.dataset_location

  # Configure access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.dataform_scheduler.email
  }

  access {
    role         = "READER"
    special_group = "projectReaders"
  }

  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }

  access {
    role         = "OWNER"
    special_group = "projectOwners"
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]

  # Prevent accidental deletion in production
  deletion_protection = var.deletion_protection
}

# Create sample customers table with intentional data quality issues
resource "google_bigquery_table" "customers" {
  count = var.create_sample_data ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.sample_dataset.dataset_id
  table_id   = "customers"

  description = "Sample customer data with intentional quality issues for testing assertions"

  schema = jsonencode([
    {
      name = "customer_id"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Unique customer identifier"
    },
    {
      name = "email"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer email address (may contain null values for testing)"
    },
    {
      name = "first_name"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer first name (may contain null values for testing)"
    },
    {
      name = "last_name"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer last name (may contain null values for testing)"
    },
    {
      name = "registration_date"
      type = "DATE"
      mode = "NULLABLE"
      description = "Date when customer registered"
    },
    {
      name = "city"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer city"
    },
    {
      name = "state"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer state"
    }
  ])

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.sample_dataset]
}

# Create sample orders table with intentional data quality issues
resource "google_bigquery_table" "orders" {
  count = var.create_sample_data ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.sample_dataset.dataset_id
  table_id   = "orders"

  description = "Sample order data with intentional quality issues for testing assertions"

  schema = jsonencode([
    {
      name = "order_id"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Unique order identifier"
    },
    {
      name = "customer_id"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Reference to customer (may contain invalid references for testing)"
    },
    {
      name = "order_date"
      type = "DATE"
      mode = "NULLABLE"
      description = "Date when order was placed"
    },
    {
      name = "total_amount"
      type = "NUMERIC"
      mode = "NULLABLE"
      description = "Total order amount (may contain negative values for testing)"
    },
    {
      name = "status"
      type = "STRING"
      mode = "NULLABLE"
      description = "Order status"
    }
  ])

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.sample_dataset]
}

# Insert sample data into customers table
resource "google_bigquery_job" "insert_sample_customers" {
  count = var.create_sample_data ? 1 : 0

  project  = var.project_id
  job_id   = "insert-sample-customers-${random_id.suffix.hex}"
  location = var.dataset_location

  query {
    query = <<-EOF
      INSERT INTO `${var.project_id}.${local.dataset_id}.customers` 
      (customer_id, email, first_name, last_name, registration_date, city, state)
      VALUES
        (1, 'john@example.com', 'John', 'Doe', '2024-01-15', 'New York', 'NY'),
        (2, 'jane@example.com', 'Jane', 'Smith', '2024-02-20', 'Los Angeles', 'CA'),
        (3, 'bob@example.com', 'Bob', 'Johnson', '2024-03-10', 'Chicago', 'IL'),
        (4, NULL, 'Alice', 'Brown', '2024-04-05', 'Houston', 'TX'),
        (5, 'charlie@example.com', NULL, 'Davis', '2024-05-12', 'Phoenix', 'AZ')
    EOF

    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.customers]
}

# Insert sample data into orders table
resource "google_bigquery_job" "insert_sample_orders" {
  count = var.create_sample_data ? 1 : 0

  project  = var.project_id
  job_id   = "insert-sample-orders-${random_id.suffix.hex}"
  location = var.dataset_location

  query {
    query = <<-EOF
      INSERT INTO `${var.project_id}.${local.dataset_id}.orders` 
      (order_id, customer_id, order_date, total_amount, status)
      VALUES
        (1, 1, '2024-06-01', 99.99, 'completed'),
        (2, 2, '2024-06-02', 149.50, 'completed'),
        (3, 3, '2024-06-03', -25.00, 'refunded'),
        (4, 999, '2024-06-04', 75.25, 'pending'),
        (5, 2, '2024-06-05', NULL, 'completed')
    EOF

    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.orders]
}

# Create Dataform repository for data quality monitoring
resource "google_dataform_repository" "quality_repository" {
  provider = google-beta

  project      = var.project_id
  region       = var.region
  name         = var.dataform_repository_name
  display_name = "Data Quality Monitoring Repository"

  # Configure workspace compilation overrides for consistent BigQuery settings
  workspace_compilation_overrides {
    default_database = var.project_id
    schema_suffix    = "_${random_id.suffix.hex}"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset.sample_dataset,
    google_bigquery_dataset.assertion_dataset
  ]
}

# Create Dataform release configuration for production deployments
resource "google_dataform_repository_release_config" "quality_release" {
  provider = google-beta

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.quality_repository.name
  name       = var.dataform_release_config_name

  # Use main branch for stable releases
  git_commitish = "main"

  # Compile with production settings
  cron_schedule = var.scheduler_frequency
  time_zone     = var.scheduler_timezone

  # Configure compilation settings
  compilation_overrides {
    default_database = var.project_id
    schema_suffix    = "_${random_id.suffix.hex}"
  }
}

# Create Cloud Scheduler job to trigger Dataform workflows
resource "google_cloud_scheduler_job" "dataform_trigger" {
  project     = var.project_id
  region      = var.region
  name        = local.scheduler_job_id
  description = var.scheduler_description
  schedule    = var.scheduler_frequency
  time_zone   = var.scheduler_timezone

  # Configure retry behavior for failed executions
  retry_config {
    retry_count          = var.scheduler_retry_count
    max_retry_duration   = "600s"
    min_backoff_duration = "5s"
    max_backoff_duration = "120s"
    max_doublings        = 3
  }

  # Set execution deadline
  attempt_deadline = var.scheduler_attempt_deadline

  # Configure HTTP target to trigger Dataform workflow
  http_target {
    http_method = "POST"
    uri         = "https://dataform.googleapis.com/v1beta1/projects/${var.project_id}/locations/${var.region}/repositories/${google_dataform_repository.quality_repository.name}/workflowInvocations"

    headers = {
      "Content-Type" = "application/json"
    }

    # Workflow invocation payload
    body = base64encode(jsonencode({
      compilationResult = "projects/${var.project_id}/locations/${var.region}/repositories/${google_dataform_repository.quality_repository.name}/compilationResults/latest"
    }))

    # Use OIDC authentication with service account
    oidc_token {
      service_account_email = google_service_account.dataform_scheduler.email
      audience             = "https://dataform.googleapis.com/"
    }
  }

  depends_on = [
    google_dataform_repository.quality_repository,
    google_project_iam_member.dataform_editor
  ]
}

# Create log-based metric for data quality failures (if monitoring enabled)
resource "google_logging_metric" "data_quality_failures" {
  count = var.enable_monitoring ? 1 : 0

  project = var.project_id
  name    = "data_quality_failures_${random_id.suffix.hex}"

  description = "Metric tracking data quality assertion failures in Dataform workflows"

  # Filter for Dataform-related log entries indicating quality issues
  filter = <<-EOF
    resource.type="dataform_repository" OR
    resource.type="bigquery_dataset" AND
    (textPayload:"assertion" OR textPayload:"quality" OR textPayload:"failed")
  EOF

  # Configure metric as a counter
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Data Quality Failures"
  }

  # Extract failure count from log entries
  value_extractor = "EXTRACT(jsonPayload.failureCount)"

  # Add labels for better filtering and grouping
  label_extractors = {
    "dataset"   = "EXTRACT(resource.labels.dataset_id)"
    "assertion" = "EXTRACT(jsonPayload.assertionName)"
  }

  depends_on = [google_project_service.required_apis]
}

# Create notification channel for email alerts (if email provided and monitoring enabled)
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  project      = var.project_id
  display_name = "Data Quality Email Alerts"
  description  = "Email notifications for data quality issues"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for data quality monitoring (if monitoring enabled)
resource "google_monitoring_alert_policy" "data_quality_alert" {
  count = var.enable_monitoring ? 1 : 0

  project      = var.project_id
  display_name = "Data Quality Failure Alert"
  description  = "Alert when data quality assertions fail or quality scores drop below acceptable thresholds"

  # Combine multiple conditions with OR logic
  combiner = "OR"

  # Alert condition for high failure rate
  conditions {
    display_name = "High Data Quality Failure Rate"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/data_quality_failures_${random_id.suffix.hex}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_threshold

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Configure alert strategy
  alert_strategy {
    auto_close = "1800s"
  }

  # Send notifications to configured channels
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []

  documentation {
    content = <<-EOF
      # Data Quality Alert

      This alert triggers when data quality issues are detected in your Dataform workflows.

      ## Troubleshooting Steps:
      1. Check the Dataform workflow execution logs
      2. Review assertion results in BigQuery
      3. Investigate data sources for quality issues
      4. Update data quality thresholds if needed

      ## Additional Resources:
      - Dataform Repository: ${google_dataform_repository.quality_repository.name}
      - Sample Dataset: ${local.dataset_id}
      - Assertion Dataset: ${local.assertion_dataset_id}
    EOF
    mime_type = "text/markdown"
  }

  enabled = true

  depends_on = [
    google_logging_metric.data_quality_failures,
    google_monitoring_notification_channel.email_alerts
  ]
}

# Create a delay to ensure APIs are fully ready
resource "time_sleep" "api_propagation" {
  depends_on = [google_project_service.required_apis]

  create_duration = "60s"
}