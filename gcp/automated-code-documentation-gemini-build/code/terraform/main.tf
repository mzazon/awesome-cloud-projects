# Main Terraform configuration for automated code documentation with Gemini and Cloud Build
# This infrastructure deploys a complete CI/CD documentation automation solution

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with prefix and random suffix
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.name_prefix}-docs-${local.resource_suffix}"
  sa_name         = "${var.name_prefix}-sa"
  
  # Function names
  doc_function_name    = "${var.name_prefix}-processor-${local.resource_suffix}"
  notify_function_name = "${var.name_prefix}-notifier-${local.resource_suffix}"
  
  # Build trigger name
  build_trigger_name = "${var.name_prefix}-trigger-${local.resource_suffix}"
  
  # Combined labels
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.apis_to_enable)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for documentation automation with least privilege access
resource "google_service_account" "doc_automation" {
  account_id   = local.sa_name
  display_name = "Documentation Automation Service Account"
  description  = "Service account for automated documentation generation using Gemini AI"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account - Vertex AI access
resource "google_project_iam_member" "sa_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.doc_automation.email}"
}

# IAM roles for the service account - Storage access
resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.doc_automation.email}"
}

# IAM roles for the service account - Cloud Functions invoker
resource "google_project_iam_member" "sa_functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.doc_automation.email}"
}

# Additional IAM roles if specified
resource "google_project_iam_member" "sa_additional_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.doc_automation.email}"
}

# Cloud Storage bucket for documentation storage with versioning and lifecycle management
resource "google_storage_bucket" "documentation_storage" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Versioning configuration for documentation history
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management to optimize storage costs
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
        num_newer_versions   = lifecycle_rule.value.condition.num_newer_versions
      }
    }
  }
  
  # Website configuration for documentation hosting
  dynamic "website" {
    for_each = var.enable_website ? [1] : []
    content {
      main_page_suffix = "index.html"
      not_found_page   = "404.html"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create source code archive for the documentation processing function
data "archive_file" "doc_function_source" {
  type        = "zip"
  output_path = "/tmp/doc-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      gemini_model = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for the documentation function source code
resource "google_storage_bucket_object" "doc_function_source" {
  name   = "function-source/doc-processor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.documentation_storage.name
  source = data.archive_file.doc_function_source.output_path
  
  depends_on = [data.archive_file.doc_function_source]
}

# Cloud Function for documentation processing using Gemini AI
resource "google_cloudfunctions2_function" "doc_processor" {
  name        = local.doc_function_name
  location    = var.region
  description = "Generate documentation using Vertex AI Gemini models"
  project     = var.project_id
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_docs"
    
    source {
      storage_source {
        bucket = google_storage_bucket.documentation_storage.name
        object = google_storage_bucket_object.doc_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    
    environment_variables = {
      BUCKET_NAME           = google_storage_bucket.documentation_storage.name
      GOOGLE_CLOUD_PROJECT  = var.project_id
      GEMINI_MODEL         = var.gemini_model
    }
    
    service_account_email = google_service_account.doc_automation.email
    
    # Ingress settings for security
    ingress_settings               = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.doc_function_source
  ]
}

# Cloud Function IAM policy for public access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "doc_processor_public" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.doc_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create source code archive for the notification function
data "archive_file" "notification_function_source" {
  count = var.enable_notifications ? 1 : 0
  
  type        = "zip"
  output_path = "/tmp/notification-function-source.zip"
  
  source {
    content  = file("${path.module}/notification-source/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/notification-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for the notification function source code
resource "google_storage_bucket_object" "notification_function_source" {
  count = var.enable_notifications ? 1 : 0
  
  name   = "function-source/notification-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.documentation_storage.name
  source = data.archive_file.notification_function_source[0].output_path
  
  depends_on = [data.archive_file.notification_function_source]
}

# Cloud Function for notifications with Eventarc trigger
resource "google_cloudfunctions2_function" "notification_processor" {
  count = var.enable_notifications ? 1 : 0
  
  name        = local.notify_function_name
  location    = var.region
  description = "Send notifications when documentation is updated"
  project     = var.project_id
  
  build_config {
    runtime     = "python312"
    entry_point = "notify_team"
    
    source {
      storage_source {
        bucket = google_storage_bucket.documentation_storage.name
        object = google_storage_bucket_object.notification_function_source[0].name
      }
    }
  }
  
  service_config {
    max_instance_count               = 5
    min_instance_count               = 0
    available_memory                 = "${var.notification_function_memory}M"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 1
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.documentation_storage.name
    }
    
    service_account_email = google_service_account.doc_automation.email
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.documentation_storage.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.notification_function_source
  ]
}

# Pub/Sub topic for Cloud Build integration (automatically created by Cloud Build)
resource "google_pubsub_topic" "cloud_build" {
  count = var.create_build_trigger ? 1 : 0
  
  name    = "cloud-builds"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Build trigger for manual documentation generation
resource "google_cloudbuild_trigger" "documentation_generation" {
  count = var.create_build_trigger ? 1 : 0
  
  name        = "${local.build_trigger_name}-manual"
  description = var.build_trigger_description
  location    = var.region
  project     = var.project_id
  
  # Manual trigger configuration
  trigger_template {
    branch_name = "main"  # Default branch for manual triggers
  }
  
  # Build configuration inline (can also reference a file)
  build {
    step {
      name = "gcr.io/cloud-builders/git"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Analyzing repository structure..."
          find . -name "*.py" -o -name "*.js" -o -name "*.go" -o -name "*.java" | head -10 > files_to_document.txt
          echo "Found files for documentation:"
          cat files_to_document.txt
        EOT
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/curl"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Generating API documentation..."
          for file in $$(grep "\\.py$$" files_to_document.txt); do
            if [ -f "$$file" ]; then
              echo "Processing $$file..."
              content=$$(cat "$$file" | head -50)
              escaped_content=$$(echo "$$content" | sed 's/"/\\"/g' | tr '\n' ' ')
              curl -X POST "${google_cloudfunctions2_function.doc_processor.service_config[0].uri}" \
                -H "Content-Type: application/json" \
                -d "{\"repo_path\":\"$$file\",\"file_content\":\"$$escaped_content\",\"doc_type\":\"api\"}" \
                -H "Authorization: Bearer $$(gcloud auth print-access-token)"
            fi
          done
        EOT
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/curl"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Generating README documentation..."
          repo_structure=$$(find . -type f -name "*.py" -o -name "*.js" -o -name "*.md" | head -20 | xargs ls -la)
          escaped_structure=$$(echo "$$repo_structure" | sed 's/"/\\"/g' | tr '\n' ' ')
          curl -X POST "${google_cloudfunctions2_function.doc_processor.service_config[0].uri}" \
            -H "Content-Type: application/json" \
            -d "{\"repo_path\":\"project_root\",\"file_content\":\"$$escaped_structure\",\"doc_type\":\"readme\"}" \
            -H "Authorization: Bearer $$(gcloud auth print-access-token)"
        EOT
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/gsutil"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
          echo "Creating documentation index..."
          echo "# Documentation Index" > index.md
          echo "Generated on: $$(date)" >> index.md
          echo "" >> index.md
          echo "## Available Documentation" >> index.md
          echo "- API Documentation: gs://${google_storage_bucket.documentation_storage.name}/api/" >> index.md
          echo "- README Files: gs://${google_storage_bucket.documentation_storage.name}/readme/" >> index.md
          echo "- Enhanced Code: gs://${google_storage_bucket.documentation_storage.name}/comments/" >> index.md
          gsutil cp index.md gs://${google_storage_bucket.documentation_storage.name}/
        EOT
      ]
    }
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    
    service_account = google_service_account.doc_automation.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.doc_processor
  ]
}

# Documentation website files (optional)
resource "google_storage_bucket_object" "website_index" {
  count = var.enable_website ? 1 : 0
  
  name   = "website/index.html"
  bucket = google_storage_bucket.documentation_storage.name
  
  content = templatefile("${path.module}/website/index.html", {
    bucket_name = google_storage_bucket.documentation_storage.name
    project_id  = var.project_id
  })
  
  content_type = "text/html"
}

# IAM binding for public website access (if enabled)
resource "google_storage_bucket_iam_member" "website_public_access" {
  count = var.enable_website ? 1 : 0
  
  bucket = google_storage_bucket.documentation_storage.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
  
  condition {
    title       = "Website files only"
    description = "Grant access only to website files"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.documentation_storage.name}/objects/website/\")"
  }
}