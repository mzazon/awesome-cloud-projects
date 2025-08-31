# =============================================================================
# Job Description Generation with Gemini and Firestore
# =============================================================================
# This Terraform configuration deploys an intelligent HR automation system that 
# generates comprehensive, compliant job descriptions using Google Cloud's 
# Vertex AI Gemini models, Firestore for data storage, and Cloud Functions 
# for serverless orchestration.
# =============================================================================

# Local values for resource naming and configuration
locals {
  # Generate unique resource names with timestamp suffix
  timestamp_suffix = formatdate("YYYYMMDD-hhmm", timestamp())
  
  # Base naming convention
  base_name = "job-description-gen"
  
  # Resource-specific names
  project_id_base    = "${var.project_id_prefix}-${local.timestamp_suffix}"
  bucket_name        = "${local.base_name}-source-${local.timestamp_suffix}"
  
  # Common labels for all resources
  common_labels = {
    application = "hr-automation"
    component   = "job-description-generator"
    environment = var.environment
    created_by  = "terraform"
    recipe      = "job-description-generation-gemini-firestore"
  }
  
  # Required APIs for the solution
  required_apis = [
    "aiplatform.googleapis.com",      # Vertex AI for Gemini models
    "firestore.googleapis.com",       # Firestore database
    "cloudfunctions.googleapis.com",  # Cloud Functions
    "cloudbuild.googleapis.com",      # Cloud Build for function deployment
    "storage.googleapis.com",         # Cloud Storage for function source
    "artifactregistry.googleapis.com" # Artifact Registry for container images
  ]
}

# =============================================================================
# Google Cloud Project Configuration
# =============================================================================

# Create a new project if requested, otherwise use existing
resource "google_project" "hr_automation" {
  count           = var.create_project ? 1 : 0
  name            = "HR Automation - Job Description Generator"
  project_id      = local.project_id_base
  billing_account = var.billing_account
  org_id          = var.org_id
  folder_id       = var.folder_id
  
  labels = local.common_labels
}

# Use the created or existing project
data "google_project" "current" {
  project_id = var.create_project ? google_project.hr_automation[0].project_id : var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project                    = data.google_project.current.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
  
  depends_on = [google_project.hr_automation]
}

# =============================================================================
# Firestore Database and Collections
# =============================================================================

# Create Firestore database in Native mode for modern NoSQL capabilities
resource "google_firestore_database" "hr_database" {
  project                           = data.google_project.current.project_id
  name                              = var.firestore_database_name
  location_id                       = var.region
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = var.enable_firestore_pitr ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  delete_protection_state           = var.firestore_delete_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = "DELETE"
  
  depends_on = [google_project_service.required_apis]
}

# Create sample company culture document
resource "google_firestore_document" "company_culture" {
  project     = data.google_project.current.project_id
  database    = google_firestore_database.hr_database.name
  collection  = "company_culture"
  document_id = "default"
  
  fields = jsonencode({
    company_name = {
      stringValue = var.company_name
    }
    mission = {
      stringValue = var.company_mission
    }
    values = {
      arrayValue = {
        values = [
          for value in var.company_values : {
            stringValue = value
          }
        ]
      }
    }
    culture_description = {
      stringValue = var.company_culture_description
    }
    benefits = {
      arrayValue = {
        values = [
          for benefit in var.company_benefits : {
            stringValue = benefit
          }
        ]
      }
    }
    work_environment = {
      stringValue = var.work_environment
    }
    created_at = {
      timestampValue = timestamp()
    }
  })
  
  depends_on = [google_firestore_database.hr_database]
}

# Create job role templates
resource "google_firestore_document" "software_engineer_template" {
  project     = data.google_project.current.project_id
  database    = google_firestore_database.hr_database.name
  collection  = "job_templates"
  document_id = "software_engineer"
  
  fields = jsonencode({
    title = {
      stringValue = "Software Engineer"
    }
    department = {
      stringValue = "Engineering"
    }
    level = {
      stringValue = "mid"
    }
    required_skills = {
      arrayValue = {
        values = [
          { stringValue = "JavaScript" },
          { stringValue = "Python" },
          { stringValue = "React" },
          { stringValue = "Node.js" },
          { stringValue = "Git" }
        ]
      }
    }
    nice_to_have = {
      arrayValue = {
        values = [
          { stringValue = "Google Cloud" },
          { stringValue = "Docker" },
          { stringValue = "GraphQL" },
          { stringValue = "TypeScript" }
        ]
      }
    }
    education = {
      stringValue = "Bachelor degree in Computer Science or equivalent experience"
    }
    experience_years = {
      stringValue = "2-4 years"
    }
    responsibilities = {
      arrayValue = {
        values = [
          { stringValue = "Develop and maintain web applications" },
          { stringValue = "Collaborate with cross-functional teams" },
          { stringValue = "Write clean, maintainable code" },
          { stringValue = "Participate in code reviews" },
          { stringValue = "Debug and troubleshoot issues" }
        ]
      }
    }
    compliance_notes = {
      stringValue = "Equal opportunity employer statement required"
    }
    created_at = {
      timestampValue = timestamp()
    }
  })
  
  depends_on = [google_firestore_database.hr_database]
}

resource "google_firestore_document" "marketing_manager_template" {
  project     = data.google_project.current.project_id
  database    = google_firestore_database.hr_database.name
  collection  = "job_templates"
  document_id = "marketing_manager"
  
  fields = jsonencode({
    title = {
      stringValue = "Marketing Manager"
    }
    department = {
      stringValue = "Marketing"
    }
    level = {
      stringValue = "senior"
    }
    required_skills = {
      arrayValue = {
        values = [
          { stringValue = "Digital Marketing" },
          { stringValue = "Campaign Management" },
          { stringValue = "Analytics" },
          { stringValue = "Content Strategy" },
          { stringValue = "SEO/SEM" }
        ]
      }
    }
    nice_to_have = {
      arrayValue = {
        values = [
          { stringValue = "Adobe Creative Suite" },
          { stringValue = "Marketing Automation" },
          { stringValue = "SQL" },
          { stringValue = "A/B Testing" }
        ]
      }
    }
    education = {
      stringValue = "Bachelor degree in Marketing, Business, or related field"
    }
    experience_years = {
      stringValue = "5-7 years"
    }
    responsibilities = {
      arrayValue = {
        values = [
          { stringValue = "Develop marketing strategies and campaigns" },
          { stringValue = "Manage marketing budget and ROI" },
          { stringValue = "Lead marketing team and initiatives" },
          { stringValue = "Analyze market trends and competitor activities" },
          { stringValue = "Drive brand awareness and lead generation" }
        ]
      }
    }
    compliance_notes = {
      stringValue = "Equal opportunity employer statement required"
    }
    created_at = {
      timestampValue = timestamp()
    }
  })
  
  depends_on = [google_firestore_database.hr_database]
}

# =============================================================================
# IAM Service Accounts and Permissions
# =============================================================================

# Service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  project      = data.google_project.current.project_id
  account_id   = "${local.base_name}-function-sa"
  display_name = "Job Description Generator Function Service Account"
  description  = "Service account for Cloud Functions that generate job descriptions using Vertex AI and Firestore"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = data.google_project.current.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_firestore_user" {
  project = data.google_project.current.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = data.google_project.current.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Build service account for Cloud Functions deployment
resource "google_service_account" "build_service_account" {
  project      = data.google_project.current.project_id
  account_id   = "${local.base_name}-build-sa"
  display_name = "Cloud Build Service Account for Function Deployment"
  description  = "Service account for Cloud Build to deploy Cloud Functions"
  
  depends_on = [google_project_service.required_apis]
}

# Build service account permissions
resource "google_project_iam_member" "build_logs_writer" {
  project = data.google_project.current.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.build_service_account.email}"
}

resource "google_project_iam_member" "build_artifact_registry_writer" {
  project = data.google_project.current.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.build_service_account.email}"
}

resource "google_project_iam_member" "build_storage_object_admin" {
  project = data.google_project.current.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.build_service_account.email}"
}

# =============================================================================
# Cloud Storage for Function Source Code
# =============================================================================

# Create storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  project                     = data.google_project.current.project_id
  name                        = local.bucket_name
  location                    = var.region
  force_destroy              = true
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
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
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code zip file
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/main.py", {
      project_id = data.google_project.current.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/templates/requirements.txt", {})
    filename = "requirements.txt"
  }
  
  source {
    content = templatefile("${path.module}/templates/compliance_validator.py", {
      project_id = data.google_project.current.project_id
      region     = var.region
    })
    filename = "compliance_validator.py"
  }
}

# Upload function source to storage bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# =============================================================================
# Cloud Functions for Job Description Generation
# =============================================================================

# Wait for build permissions to propagate
resource "time_sleep" "wait_for_build_permissions" {
  create_duration = "60s"
  
  depends_on = [
    google_project_iam_member.build_logs_writer,
    google_project_iam_member.build_artifact_registry_writer,
    google_project_iam_member.build_storage_object_admin
  ]
}

# Main job description generation function
resource "google_cloudfunctions2_function" "generate_job_description" {
  project     = data.google_project.current.project_id
  name        = "${local.base_name}-generator"
  location    = var.region
  description = "Generates job descriptions using Vertex AI Gemini and Firestore data"
  
  labels = local.common_labels
  
  build_config {
    runtime                = "python311"
    entry_point           = "generate_job_description_http"
    service_account       = google_service_account.build_service_account.id
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = var.function_min_instances
    available_memory                = var.function_memory
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 10
    service_account_email           = google_service_account.function_service_account.email
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    environment_variables = {
      GCP_PROJECT     = data.google_project.current.project_id
      FUNCTION_REGION = var.region
      FIRESTORE_DB    = google_firestore_database.hr_database.name
      GEMINI_MODEL    = var.gemini_model
    }
  }
  
  depends_on = [
    time_sleep.wait_for_build_permissions,
    google_firestore_document.company_culture,
    google_firestore_document.software_engineer_template,
    google_firestore_document.marketing_manager_template
  ]
}

# Compliance validation function
resource "google_cloudfunctions2_function" "validate_compliance" {
  project     = data.google_project.current.project_id
  name        = "${local.base_name}-compliance"
  location    = var.region
  description = "Validates job descriptions for compliance using Vertex AI Gemini"
  
  labels = local.common_labels
  
  build_config {
    runtime                = "python311"
    entry_point           = "validate_compliance"
    service_account       = google_service_account.build_service_account.id
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = 0
    available_memory                = "256Mi"
    timeout_seconds                 = 60
    max_instance_request_concurrency = 10
    service_account_email           = google_service_account.function_service_account.email
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    environment_variables = {
      GCP_PROJECT     = data.google_project.current.project_id
      FUNCTION_REGION = var.region
      GEMINI_MODEL    = var.gemini_model
    }
  }
  
  depends_on = [
    time_sleep.wait_for_build_permissions
  ]
}

# =============================================================================
# IAM for Function Access
# =============================================================================

# Allow unauthenticated access to generation function (adjust based on requirements)
resource "google_cloudfunctions2_function_iam_member" "generator_invoker" {
  project        = data.google_project.current.project_id
  location       = google_cloudfunctions2_function.generate_job_description.location
  cloud_function = google_cloudfunctions2_function.generate_job_description.name
  role           = "roles/cloudfunctions.invoker"
  member         = var.allow_unauthenticated_access ? "allUsers" : "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_cloudfunctions2_function_iam_member" "compliance_invoker" {
  project        = data.google_project.current.project_id
  location       = google_cloudfunctions2_function.validate_compliance.location
  cloud_function = google_cloudfunctions2_function.validate_compliance.name
  role           = "roles/cloudfunctions.invoker"
  member         = var.allow_unauthenticated_access ? "allUsers" : "serviceAccount:${google_service_account.function_service_account.email}"
}

# =============================================================================
# Monitoring and Logging (Optional)
# =============================================================================

# Create log-based metric for function errors
resource "google_logging_metric" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.base_name}-function-errors"
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"${local.base_name}.*"
    severity>=ERROR
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Job Description Function Errors"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create log-based metric for successful generations
resource "google_logging_metric" "successful_generations" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.base_name}-successful-generations"
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.generate_job_description.name}"
    jsonPayload.success=true
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Successful Job Description Generations"
  }
  
  depends_on = [google_project_service.required_apis]
}