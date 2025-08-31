# Main Terraform configuration for automated code refactoring infrastructure
# This creates a complete CI/CD pipeline with AI-powered code refactoring capabilities

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming with random suffix
  resource_suffix = random_id.suffix.hex
  
  # Required Google Cloud APIs for the solution
  required_apis = [
    "sourcerepo.googleapis.com",     # Source Repositories API
    "cloudbuild.googleapis.com",     # Cloud Build API
    "cloudaicompanion.googleapis.com", # Gemini Code Assist API
    "serviceusage.googleapis.com",   # Service Usage API for API management
    "cloudresourcemanager.googleapis.com", # Resource Manager API
  ]
  
  # Service account roles for automated refactoring
  service_account_roles = [
    "roles/source.writer",           # Write access to Source Repositories
    "roles/cloudaicompanion.user",   # Access to Gemini Code Assist
    "roles/cloudbuild.builds.editor", # Manage Cloud Build operations
    "roles/logging.logWriter",       # Write build logs
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when Terraform is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Google Cloud Source Repository for code storage
resource "google_sourcerepo_repository" "refactoring_repo" {
  name    = "${var.repository_name}-${local.resource_suffix}"
  project = var.project_id
  
  # Apply labels for resource management
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Build automation
resource "google_service_account" "refactor_service_account" {
  account_id   = "${var.service_account_name}-${local.resource_suffix}"
  display_name = "Automated Refactoring Service Account"
  description  = "Service account for AI-powered code refactoring workflows with Cloud Build"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Assign necessary IAM roles to the service account
resource "google_project_iam_member" "service_account_roles" {
  for_each = toset(local.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.refactor_service_account.email}"
  
  depends_on = [google_service_account.refactor_service_account]
}

# Create Cloud Build trigger for automated refactoring pipeline
resource "google_cloudbuild_trigger" "refactoring_trigger" {
  name        = "${var.build_trigger_name}-${local.resource_suffix}"
  description = "Automated code refactoring trigger with AI assistance"
  project     = var.project_id
  location    = var.region
  
  # Trigger configuration for Source Repository
  source_to_build {
    uri       = google_sourcerepo_repository.refactoring_repo.url
    ref       = "refs/heads/main"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  # Git trigger configuration
  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = google_sourcerepo_repository.refactoring_repo.url
    revision  = "refs/heads/main"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  # Advanced trigger settings
  included_files = ["**/*.py", "**/*.js", "**/*.ts", "**/*.java", "**/*.go"]
  
  # Service account for build execution
  service_account = google_service_account.refactor_service_account.id
  
  # Build configuration
  build {
    # Build timeout configuration
    timeout = "${var.build_timeout}s"
    
    # Build machine configuration
    options {
      machine_type = var.build_machine_type
      
      # Enhanced logging for debugging
      logging = "CLOUD_LOGGING_ONLY"
      
      # Security options
      log_streaming_option = "STREAM_ON"
      
      # Worker pool configuration for performance
      dynamic_substitutions = true
    }
    
    # Build steps for automated refactoring
    step {
      name = "gcr.io/cloud-builders/git"
      args = [
        "config",
        "user.email",
        "refactor-bot@${var.project_id}.iam.gserviceaccount.com"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/git"
      args = [
        "config",
        "user.name",
        "Automated Refactor Bot"
      ]
    }
    
    step {
      name       = "gcr.io/cloud-builders/python"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        echo "Starting AI-powered code analysis..."
        python3 -m pip install --upgrade pip
        pip3 install requests
        python3 analyze_and_refactor.py || echo "Analysis completed with warnings"
        EOT
      ]
    }
    
    step {
      name       = "gcr.io/cloud-builders/python"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        echo "Applying refactoring suggestions..."
        if [ -f "main_refactored.py" ]; then
          mv main_refactored.py main.py
          echo "✅ Refactoring applied successfully"
        else
          echo "No refactoring changes generated"
        fi
        EOT
      ]
    }
    
    step {
      name       = "gcr.io/cloud-builders/git"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        BRANCH_NAME="refactor/ai-improvements-$(date +%s)"
        echo "Creating refactoring branch: $BRANCH_NAME"
        
        # Check if there are changes to commit
        if git diff --quiet && git diff --cached --quiet; then
          echo "No changes detected, skipping branch creation"
          exit 0
        fi
        
        # Create and switch to new branch
        git checkout -b "$BRANCH_NAME"
        
        # Add refactored files
        git add -A
        
        # Commit with detailed message
        git commit -m "🤖 AI-powered code refactoring

        Applied automated improvements:
        - Code quality analysis with AI assistance
        - Best practice recommendations applied
        - Maintainability improvements implemented
        
        Generated by automated refactoring workflow."
        
        # Push the branch
        git push origin "$BRANCH_NAME"
        
        echo "✅ Refactoring branch created: $BRANCH_NAME"
        echo "Navigate to Source Repositories console to create pull request"
        EOT
      ]
    }
    
    # Build substitutions for customization
    substitutions = var.substitutions
  }
  
  # Apply labels for resource management
  tags = keys(var.labels)
  
  depends_on = [
    google_sourcerepo_repository.refactoring_repo,
    google_service_account.refactor_service_account,
    google_project_iam_member.service_account_roles
  ]
}

# Optional: Create Cloud Storage bucket for build logs if specified
resource "google_storage_bucket" "build_logs" {
  count    = var.log_bucket != "" ? 1 : 0
  name     = var.log_bucket
  location = var.region
  project  = var.project_id
  
  # Bucket configuration for build logs
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for log retention
  versioning {
    enabled = true
  }
  
  # Labels for resource management
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Grant service account access to build logs bucket
resource "google_storage_bucket_iam_member" "build_logs_access" {
  count  = var.log_bucket != "" ? 1 : 0
  bucket = google_storage_bucket.build_logs[0].name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.refactor_service_account.email}"
  
  depends_on = [google_storage_bucket.build_logs]
}

# Create Cloud Build worker pool for enhanced performance (optional)
resource "google_cloudbuild_worker_pool" "refactoring_pool" {
  count    = var.build_machine_type == "E2_HIGHCPU_32" ? 1 : 0
  name     = "refactoring-pool-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  worker_config {
    machine_type   = var.build_machine_type
    disk_size_gb   = 100
    no_external_ip = false
  }
  
  depends_on = [google_project_service.required_apis]
}