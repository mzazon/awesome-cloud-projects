# =============================================================================
# Training Data Quality Assessment with Vertex AI and Cloud Functions
# =============================================================================
# This Terraform configuration deploys an automated data quality assessment 
# system using Vertex AI's Gemini models integrated with Cloud Functions
# for serverless processing of training datasets.

# Configure the Terraform backend (optional - uncomment for state management)
# terraform {
#   backend "gcs" {
#     bucket = "your-terraform-state-bucket"
#     prefix = "training-data-quality"
#   }
# }

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get the current project information
data "google_project" "current" {}

# Get the current client configuration
data "google_client_config" "current" {}

# -----------------------------------------------------------------------------
# Random Resources for Unique Naming
# -----------------------------------------------------------------------------

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# -----------------------------------------------------------------------------
# Cloud Storage Bucket for Data and Reports
# -----------------------------------------------------------------------------

# Primary bucket for training data and analysis reports
resource "google_storage_bucket" "data_quality_bucket" {
  name                        = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy              = var.force_destroy_bucket

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle rules for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Public access prevention
  public_access_prevention = "enforced"

  labels = {
    environment = var.environment
    purpose     = "training-data-quality"
    managed-by  = "terraform"
  }
}

# Create folders structure in the bucket
resource "google_storage_bucket_object" "datasets_folder" {
  name   = "datasets/"
  bucket = google_storage_bucket.data_quality_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "reports_folder" {
  name   = "reports/"
  bucket = google_storage_bucket.data_quality_bucket.name
  content = " "
}

# Upload sample training data for testing
resource "google_storage_bucket_object" "sample_data" {
  name   = "datasets/sample_training_data.json"
  bucket = google_storage_bucket.data_quality_bucket.name
  content = jsonencode([
    {
      text        = "The software engineer completed the project efficiently"
      label       = "positive"
      demographic = "male"
    },
    {
      text        = "She managed to finish the coding task adequately"
      label       = "neutral"
      demographic = "female"
    },
    {
      text        = "The developer showed exceptional problem-solving skills"
      label       = "positive"
      demographic = "male"
    },
    {
      text        = "The female programmer handled the assignment reasonably well"
      label       = "neutral"
      demographic = "female"
    },
    {
      text        = "Outstanding technical leadership demonstrated throughout"
      label       = "positive"
      demographic = "male"
    },
    {
      text        = "The code review was completed satisfactorily"
      label       = "neutral"
      demographic = "female"
    },
    {
      text        = "Innovative solution developed with great expertise"
      label       = "positive"
      demographic = "male"
    },
    {
      text        = "The documentation was prepared appropriately"
      label       = "neutral"
      demographic = "female"
    },
    {
      text        = "Excellent debugging skills resolved complex issues"
      label       = "positive"
      demographic = "male"
    },
    {
      text        = "Task completed according to basic requirements"
      label       = "neutral"
      demographic = "female"
    }
  ])
}

# -----------------------------------------------------------------------------
# Service Account for Cloud Function
# -----------------------------------------------------------------------------

# Dedicated service account for the data quality analysis function
resource "google_service_account" "function_sa" {
  account_id   = "${var.service_account_prefix}-${random_id.suffix.hex}"
  display_name = "Data Quality Analysis Function Service Account"
  description  = "Service account for data quality analysis Cloud Function with Vertex AI access"
}

# Grant Vertex AI User role for Gemini API access
resource "google_project_iam_member" "function_vertex_ai" {
  project = data.google_project.current.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Storage Object Admin role for bucket access
resource "google_project_iam_member" "function_storage" {
  project = data.google_project.current.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Functions Invoker role (for HTTP trigger)
resource "google_project_iam_member" "function_invoker" {
  project = data.google_project.current.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# -----------------------------------------------------------------------------
# Cloud Function Source Code Archive
# -----------------------------------------------------------------------------

# Create the function source code archive
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content  = file("${path.module}/function_source/main.py")
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOT
google-cloud-aiplatform==1.102.0
google-cloud-storage==2.18.0
google-cloud-functions-framework==3.8.0
pandas==2.2.3
numpy==1.26.4
scikit-learn==1.5.2
google-genai==0.3.0
EOT
}

# Create ZIP archive for Cloud Function deployment
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function.zip"
  source_dir  = "${path.module}/function_source"

  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.data_quality_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# -----------------------------------------------------------------------------
# Cloud Function for Data Quality Analysis
# -----------------------------------------------------------------------------

# Deploy the data quality analysis Cloud Function
resource "google_cloudfunctions_function" "data_quality_analyzer" {
  name                  = "${var.function_name_prefix}-${random_id.suffix.hex}"
  region                = var.region
  description           = "Automated training data quality assessment using Vertex AI and bias detection"
  runtime               = "python312"
  available_memory_mb   = 1024
  timeout               = 540
  entry_point          = "analyze_data_quality"
  service_account_email = google_service_account.function_sa.email

  # HTTP trigger configuration
  trigger {
    http_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  # Source code from Cloud Storage
  source_archive_bucket = google_storage_bucket.data_quality_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name

  # Environment variables
  environment_variables = {
    PROJECT_ID = data.google_project.current.project_id
    REGION     = var.region
  }

  # Labels for resource management
  labels = {
    environment = var.environment
    purpose     = "training-data-quality"
    managed-by  = "terraform"
  }

  depends_on = [
    google_project_iam_member.function_vertex_ai,
    google_project_iam_member.function_storage,
    google_storage_bucket_object.function_source
  ]
}

# Allow unauthenticated invocation (for testing)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count          = var.allow_unauthenticated ? 1 : 0
  project        = data.google_project.current.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.data_quality_analyzer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# -----------------------------------------------------------------------------
# Cloud Storage Notification (Optional - for automated triggers)
# -----------------------------------------------------------------------------

# Pub/Sub topic for Cloud Storage notifications
resource "google_pubsub_topic" "data_upload_notifications" {
  count = var.enable_automatic_analysis ? 1 : 0
  name  = "${var.pubsub_topic_prefix}-${random_id.suffix.hex}"

  labels = {
    environment = var.environment
    purpose     = "training-data-quality"
    managed-by  = "terraform"
  }
}

# Cloud Storage notification to trigger analysis on new data uploads
resource "google_storage_notification" "data_upload_trigger" {
  count           = var.enable_automatic_analysis ? 1 : 0
  bucket          = google_storage_bucket.data_quality_bucket.name
  payload_format  = "JSON_API_V1"
  topic           = google_pubsub_topic.data_upload_notifications[0].id
  object_name_prefix = "datasets/"
  event_types     = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# Grant Cloud Storage service account permission to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  count  = var.enable_automatic_analysis ? 1 : 0
  topic  = google_pubsub_topic.data_upload_notifications[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# Cloud Monitoring Dashboard (Optional)
# -----------------------------------------------------------------------------

# Custom dashboard for monitoring data quality analysis
resource "google_monitoring_dashboard" "data_quality_dashboard" {
  count        = var.create_monitoring_dashboard ? 1 : 0
  display_name = "Training Data Quality Analysis Dashboard"

  dashboard_json = jsonencode({
    displayName = "Training Data Quality Analysis Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Function Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.data_quality_analyzer.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Execution Duration"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.data_quality_analyzer.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = [google_cloudfunctions_function.data_quality_analyzer]
}