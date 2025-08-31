# Tax Calculator API Infrastructure with Cloud Functions and Firestore
# This Terraform configuration deploys a serverless tax calculation API on Google Cloud

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed configurations
locals {
  function_name_calculator = "${var.function_name_prefix}-${random_id.suffix.hex}"
  function_name_history    = "${var.function_name_prefix}-history-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "tax-calculator-api"
  })
  
  # Source code path for Cloud Functions
  source_dir = "${path.module}/../function-source"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling of APIs when Terraform is destroyed
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Firestore Database Configuration
# Create Firestore database in Native mode for ACID transactions and real-time updates
resource "google_firestore_database" "tax_calculator_db" {
  provider = google-beta
  
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location_id
  type        = "FIRESTORE_NATIVE"
  
  # Point-in-time recovery settings
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # Delete protection for production environments
  delete_protection_state = var.delete_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy        = "DELETE"
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for storing Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-tax-calculator-functions-${random_id.suffix.hex}"
  project  = var.project_id
  location = var.region
  
  # Lifecycle management to clean up old function versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for function source code history
  versioning {
    enabled = true
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code files
resource "local_file" "function_main" {
  filename = "${local.source_dir}/main.py"
  content = templatefile("${path.module}/function-source/main.py.tpl", {
    firestore_project_id = var.project_id
  })
  
  # Create directory if it doesn't exist
  depends_on = [null_resource.create_source_dir]
}

resource "local_file" "function_requirements" {
  filename = "${local.source_dir}/requirements.txt"
  content  = file("${path.module}/function-source/requirements.txt")
  
  depends_on = [null_resource.create_source_dir]
}

resource "null_resource" "create_source_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${local.source_dir}"
  }
}

# Create ZIP archive of function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = "${path.module}/tax-calculator-function.zip"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "tax-calculator-function-${data.archive_file.function_source_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path
  
  metadata = {
    "source-hash" = data.archive_file.function_source_zip.output_md5
  }
}

# Tax Calculator Cloud Function
# Handles POST requests for calculating income tax based on user input
resource "google_cloudfunctions_function" "tax_calculator" {
  name     = local.function_name_calculator
  project  = var.project_id
  region   = var.region
  runtime  = var.python_runtime
  
  # Function configuration
  available_memory_mb   = var.calculator_function_memory
  timeout              = var.calculator_function_timeout
  entry_point          = "calculate_tax"
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    http_trigger {}
  }
  
  # Environment variables
  environment_variables = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    FUNCTION_TARGET      = "calculate_tax"
  }
  
  # Resource limits and scaling
  max_instances = var.calculator_max_instances
  min_instances = var.min_instances
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    function-type = "tax-calculator"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.tax_calculator_db
  ]
}

# Calculation History Cloud Function
# Handles GET requests for retrieving user's tax calculation history
resource "google_cloudfunctions_function" "calculation_history" {
  name     = local.function_name_history
  project  = var.project_id
  region   = var.region
  runtime  = var.python_runtime
  
  # Function configuration optimized for read operations
  available_memory_mb   = var.history_function_memory
  timeout              = var.history_function_timeout
  entry_point          = "get_calculation_history"
  
  # Source code configuration (same as calculator function)
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    http_trigger {}
  }
  
  # Environment variables
  environment_variables = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    FUNCTION_TARGET      = "get_calculation_history"
  }
  
  # Resource limits and scaling (optimized for read workloads)
  max_instances = var.history_max_instances
  min_instances = var.min_instances
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    function-type = "calculation-history"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.tax_calculator_db
  ]
}

# IAM bindings for Cloud Functions to access Firestore
# Grant Cloud Functions service account permission to read/write Firestore data
resource "google_project_iam_member" "functions_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# Allow unauthenticated access to Cloud Functions (if enabled)
resource "google_cloudfunctions_function_iam_member" "calculator_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  region         = google_cloudfunctions_function.tax_calculator.region
  cloud_function = google_cloudfunctions_function.tax_calculator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "history_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  region         = google_cloudfunctions_function.calculation_history.region
  cloud_function = google_cloudfunctions_function.calculation_history.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Logging configuration for function monitoring
resource "google_logging_project_sink" "function_logs" {
  name        = "tax-calculator-function-logs-${random_id.suffix.hex}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}"
  
  # Log filter for Cloud Functions
  filter = <<-EOT
    resource.type="cloud_function"
    (resource.labels.function_name="${google_cloudfunctions_function.tax_calculator.name}" OR
     resource.labels.function_name="${google_cloudfunctions_function.calculation_history.name}")
  EOT
  
  # Use unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Logging permission to write to Cloud Storage
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}