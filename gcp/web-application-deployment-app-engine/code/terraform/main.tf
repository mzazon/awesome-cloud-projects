# Main Terraform configuration for deploying a Flask web application to Google App Engine
# This configuration creates all necessary resources including API enablement, application files,
# and App Engine deployment with automatic scaling

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Application = var.application_name
    Region      = var.region
  })
  
  # Application source files configuration
  app_files = {
    "main.py" = {
      content = templatefile("${path.module}/templates/main.py.tpl", {
        app_name = var.application_name
      })
    }
    "requirements.txt" = {
      content = templatefile("${path.module}/templates/requirements.txt.tpl", {})
    }
    "app.yaml" = {
      content = templatefile("${path.module}/templates/app.yaml.tpl", {
        runtime                 = var.app_engine_runtime
        min_instances          = var.min_instances
        max_instances          = var.max_instances
        target_cpu_utilization = var.target_cpu_utilization
        environment_variables  = var.environment_variables
      })
    }
    "templates/index.html" = {
      content = templatefile("${path.module}/templates/index.html.tpl", {
        app_name = var.application_name
      })
    }
    "static/style.css" = {
      content = file("${path.module}/templates/style.css")
    }
    "static/script.js" = {
      content = file("${path.module}/templates/script.js")
    }
  }
}

# Enable required Google Cloud APIs for App Engine deployment
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "appengine.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : toset([])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create App Engine application
# Note: App Engine applications cannot be deleted, only disabled
resource "google_app_engine_application" "app" {
  project       = var.project_id
  location_id   = var.region
  database_type = "CLOUD_DATASTORE_COMPATIBILITY"
  
  # Lifecycle rule to prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create a temporary directory for application files
resource "local_file" "app_files" {
  for_each = local.app_files
  
  filename = "${path.root}/temp_app/${each.key}"
  content  = each.value.content
  
  # Ensure directory structure exists
  depends_on = [null_resource.create_directories]
}

# Create necessary directories for the application structure
resource "null_resource" "create_directories" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.root}/temp_app/templates
      mkdir -p ${path.root}/temp_app/static
    EOT
  }
}

# Create a ZIP archive of the application source code
data "archive_file" "app_source" {
  type        = "zip"
  output_path = "${path.root}/app-source-${random_id.suffix.hex}.zip"
  source_dir  = "${path.root}/temp_app"
  
  depends_on = [local_file.app_files]
}

# Upload the application source to Google Cloud Storage
resource "google_storage_bucket" "app_source" {
  name          = "${var.project_id}-appengine-source-${random_id.suffix.hex}"
  location      = "US"
  force_destroy = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Apply lifecycle rules to manage storage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_tags
}

# Upload the application ZIP file to Cloud Storage
resource "google_storage_bucket_object" "app_source" {
  name   = "app-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.app_source.name
  source = data.archive_file.app_source.output_path
  
  # Ensure the object is recreated when the source changes
  detect_md5hash = data.archive_file.app_source.output_md5
}

# Deploy the application version to App Engine
resource "google_app_engine_standard_app_version" "app_version" {
  project    = var.project_id
  service    = "default"
  version_id = "v${random_id.suffix.hex}"
  runtime    = var.app_engine_runtime
  
  # Configure automatic scaling
  automatic_scaling {
    min_instances = var.min_instances
    max_instances = var.max_instances
    
    standard_scheduler_settings {
      target_cpu_utilization        = var.target_cpu_utilization
      target_throughput_utilization = 0.75
      min_instances                 = var.min_instances
      max_instances                 = var.max_instances
    }
  }
  
  # Deployment configuration from Cloud Storage
  deployment {
    zip {
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app_source.name}/${google_storage_bucket_object.app_source.name}"
    }
  }
  
  # Environment variables for the application
  env_variables = var.environment_variables
  
  # Configure instance class for performance
  instance_class = "F1"
  
  # Static file handlers for CSS and JavaScript
  handlers {
    url_regex        = "/static/(.*)"
    static_files     = "static/\\1"
    upload_path_regex = "static/(.*)"
    
    # Cache static files for better performance
    expiration = "1d"
  }
  
  # Main application handler
  handlers {
    url_regex   = ".*"
    script_path = "auto"
  }
  
  # Application lifecycle management
  delete_service_on_destroy = false
  
  depends_on = [
    google_app_engine_application.app,
    google_storage_bucket_object.app_source
  ]
}

# Configure traffic allocation to route 100% traffic to the new version
resource "google_app_engine_service_split_traffic" "app_traffic" {
  project = var.project_id
  service = google_app_engine_standard_app_version.app_version.service
  
  migrate_traffic = false
  
  split {
    shard_by = "IP"
    
    allocations = {
      (google_app_engine_standard_app_version.app_version.version_id) = 1
    }
  }
  
  depends_on = [google_app_engine_standard_app_version.app_version]
}

# Clean up temporary files after deployment
resource "null_resource" "cleanup" {
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf ${path.root}/temp_app
      rm -f ${path.root}/app-source-*.zip
    EOT
  }
  
  depends_on = [
    google_app_engine_standard_app_version.app_version,
    google_app_engine_service_split_traffic.app_traffic
  ]
}