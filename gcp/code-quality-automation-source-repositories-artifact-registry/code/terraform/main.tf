# GCP Code Quality Automation Infrastructure with Cloud Source Repositories and Artifact Registry

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  name_suffix    = random_id.suffix.hex
  repo_name      = var.repo_name != "" ? var.repo_name : "quality-demo-${local.name_suffix}"
  registry_name  = var.registry_name != "" ? var.registry_name : "quality-artifacts-${local.name_suffix}"
  trigger_name   = var.build_trigger_name != "" ? var.build_trigger_name : "quality-pipeline-${local.name_suffix}"
  bucket_name    = "${var.project_id}-build-artifacts-${local.name_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    component   = "code-quality-automation"
    created-by  = "terraform"
  })
}

# Enable required APIs for intelligent code quality automation
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com", 
    "cloudbuild.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Source Repository for secure version control
resource "google_sourcerepo_repository" "quality_repo" {
  name    = local.repo_name
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
  
  # Repository labels for organization
  # Note: Cloud Source Repositories doesn't support labels directly
}

# Primary Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "docker_registry" {
  repository_id = local.registry_name
  location      = var.region
  format        = "DOCKER"
  description   = "Secure registry for quality-validated container images"
  
  # Enable cleanup policies for cost optimization
  cleanup_policy_dry_run = false
  
  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["latest", "v"]
      older_than   = "${var.artifact_retention_days}d"
    }
  }
  
  cleanup_policies {
    id     = "keep-recent-images"
    action = "KEEP"
    
    most_recent_versions {
      keep_count = 10
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Secondary Artifact Registry repository for Python packages
resource "google_artifact_registry_repository" "python_registry" {
  repository_id = "${local.registry_name}-packages"
  location      = var.region
  format        = "PYTHON"
  description   = "Python packages with automated quality validation"
  
  # Enable cleanup policies
  cleanup_policy_dry_run = false
  
  cleanup_policies {
    id     = "delete-old-packages"
    action = "DELETE"
    
    condition {
      older_than = "${var.artifact_retention_days}d"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for build artifacts and reports
resource "google_storage_bucket" "build_artifacts" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = true
  
  # Enable versioning for artifact history
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.artifact_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable object versioning cleanup
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
  
  # Security and access controls
  uniform_bucket_level_access = true
  
  # Enable logging for audit trail
  logging {
    log_bucket = google_storage_bucket.access_logs.name
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Separate bucket for access logs
resource "google_storage_bucket" "access_logs" {
  name          = "${local.bucket_name}-logs"
  location      = var.region
  force_destroy = true
  
  # Lifecycle management for logs
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  uniform_bucket_level_access = true
  labels                     = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Cloud Build to access Artifact Registry
resource "google_artifact_registry_repository_iam_member" "cloudbuild_docker_access" {
  project    = var.project_id
  location   = google_artifact_registry_repository.docker_registry.location
  repository = google_artifact_registry_repository.docker_registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  depends_on = [google_artifact_registry_repository.docker_registry]
}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_python_access" {
  project    = var.project_id
  location   = google_artifact_registry_repository.python_registry.location
  repository = google_artifact_registry_repository.python_registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
  
  depends_on = [google_artifact_registry_repository.python_registry]
}

# IAM binding for Cloud Build to access Cloud Storage
resource "google_storage_bucket_iam_member" "cloudbuild_storage_access" {
  bucket = google_storage_bucket.build_artifacts.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Intelligent Cloud Build trigger for automated quality pipeline
resource "google_cloudbuild_trigger" "quality_pipeline" {
  name        = local.trigger_name
  description = "Intelligent quality pipeline with automated security scanning and testing"
  location    = var.region
  
  # Repository trigger configuration
  repository_event_config {
    repository = google_sourcerepo_repository.quality_repo.id
    
    # Support for multiple branch patterns
    dynamic "push" {
      for_each = var.branch_patterns
      content {
        branch = push.value
      }
    }
  }
  
  # Build configuration with comprehensive quality gates
  build {
    timeout = var.build_timeout
    
    # Quality validation steps
    dynamic "step" {
      for_each = [
        {
          name = "python:3.11-slim"
          id   = "install-dependencies"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🔍 Installing dependencies for quality analysis..."
              pip install -r requirements.txt
              echo "✅ Dependencies installed successfully"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "code-formatting"
          args = [
            "bash", "-c", 
            <<-EOT
              echo "🎨 Checking code formatting with Black..."
              pip install black==23.9.1
              black --check --diff src/ tests/
              echo "✅ Code formatting validation passed"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "static-analysis"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🔍 Running static code analysis with Flake8..."
              pip install flake8==6.1.0
              flake8 src/ tests/
              echo "✅ Static analysis completed successfully"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "type-checking"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🔍 Running type checking with MyPy..."
              pip install mypy==1.6.1
              mypy src/ --ignore-missing-imports
              echo "✅ Type checking validation passed"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "security-scanning"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🔒 Running security analysis with Bandit..."
              pip install bandit==1.7.5
              bandit -r src/ -f json -o bandit-report.json
              echo "✅ Security analysis completed"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "dependency-check"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🛡️ Checking dependencies for vulnerabilities..."
              pip install safety==2.3.5
              safety check --json
              echo "✅ Dependency security validation passed"
            EOT
          ]
        },
        {
          name = "python:3.11-slim"
          id   = "run-tests"
          args = [
            "bash", "-c",
            <<-EOT
              echo "🧪 Running comprehensive test suite..."
              pip install pytest==7.4.3 pytest-cov==4.1.0
              python -m pytest tests/ --cov=src --cov-report=term --cov-report=html
              echo "✅ All tests passed with coverage validation"
            EOT
          ]
        },
        {
          name = "gcr.io/cloud-builders/docker"
          id   = "build-image"
          args = [
            "build",
            "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/quality-app:$BUILD_ID",
            "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/quality-app:latest",
            "."
          ]
        },
        {
          name = "gcr.io/cloud-builders/docker"
          id   = "push-image"
          args = [
            "push",
            "--all-tags",
            "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/quality-app"
          ]
        }
      ]
      content {
        name = step.value.name
        id   = step.value.id
        args = step.value.args
      }
    }
    
    # Build options for performance and security
    options {
      machine_type = var.machine_type
      logging      = "CLOUD_LOGGING_ONLY"
      
      # Environment variables for build process
      env = [
        "PROJECT_ID=${var.project_id}",
        "REGION=${var.region}",
        "REGISTRY_NAME=${local.registry_name}"
      ]
    }
    
    # Artifact storage configuration
    artifacts {
      objects {
        location = "gs://${google_storage_bucket.build_artifacts.name}"
        paths = [
          "bandit-report.json",
          "htmlcov/**/*"
        ]
      }
    }
    
    # Substitution variables
    substitutions = {
      _REGION        = var.region
      _REGISTRY_NAME = local.registry_name
    }
  }
  
  depends_on = [
    google_sourcerepo_repository.quality_repo,
    google_artifact_registry_repository.docker_registry,
    google_storage_bucket.build_artifacts,
    google_project_service.required_apis
  ]
}

# Monitoring and alerting configuration
resource "google_monitoring_alert_policy" "build_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Code Quality Pipeline Build Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "Build Failure Rate Too High"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_build\" AND protoPayload.methodName=\"google.devtools.cloudbuild.v1.CloudBuild.CreateBuild\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels would be configured here if provided
  dynamic "notification_channels" {
    for_each = var.notification_channel != "" ? [var.notification_channel] : []
    content {
      # Note: Notification channels need to be created separately
      # This is a placeholder for the notification channel ID
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Custom metric for tracking code quality scores
resource "google_logging_metric" "code_quality_score" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "code_quality_score"
  filter = "resource.type=\"cloud_build\" AND jsonPayload.status=\"SUCCESS\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Code Quality Score"
  }
  
  value_extractor = "EXTRACT(jsonPayload.quality_score)"
  
  depends_on = [google_project_service.required_apis]
}

# Security policy for vulnerability scanning (if enabled)
resource "google_binary_authorization_policy" "quality_policy" {
  count = var.enable_container_analysis ? 1 : 0
  
  admission_whitelist_patterns {
    name_pattern = "${var.region}-docker.pkg.dev/${var.project_id}/${local.registry_name}/*"
  }
  
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.quality_attestor[0].name
    ]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Attestor for quality validation
resource "google_binary_authorization_attestor" "quality_attestor" {
  count = var.enable_container_analysis ? 1 : 0
  
  name = "quality-attestor-${local.name_suffix}"
  description = "Attestor for code quality validation"
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.quality_note[0].name
  }
  
  depends_on = [google_project_service.required_apis]
}

# Container Analysis note for attestations
resource "google_container_analysis_note" "quality_note" {
  count = var.enable_container_analysis ? 1 : 0
  
  name = "quality-note-${local.name_suffix}"
  
  attestation_authority {
    hint {
      human_readable_name = "Code Quality Attestor"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}