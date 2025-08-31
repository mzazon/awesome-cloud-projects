# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and configuration
locals {
  # Combine environment and random suffix for unique naming
  resource_suffix = "${var.environment}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    recipe      = "visitor-counter-functions-firestore"
  })
  
  # Function source directory (relative to this Terraform configuration)
  function_source_dir = "${path.module}/../function-source"
  
  # Generated ZIP file path for Cloud Function deployment
  function_zip_path = "${path.module}/function-source.zip"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.apis_to_enable)
  
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database (Native mode for real-time features)
resource "google_firestore_database" "visitor_counter_db" {
  project                     = var.project_id
  name                        = "(default)"
  location_id                 = var.firestore_location
  type                        = var.firestore_type
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  # Ensure APIs are enabled before creating database
  depends_on = [
    google_project_service.apis
  ]
  
  # Add timeout for database creation
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Create the function source code files if they don't exist
resource "local_file" "package_json" {
  filename = "${local.function_source_dir}/package.json"
  content = jsonencode({
    name        = "visit-counter"
    version     = "1.0.0"
    description = "Simple visitor counter using Cloud Functions and Firestore"
    main        = "index.js"
    engines = {
      node = "20"
    }
    dependencies = {
      "@google-cloud/firestore"          = "^7.1.0"
      "@google-cloud/functions-framework" = "^3.3.0"
    }
  })
}

resource "local_file" "function_code" {
  filename = "${local.function_source_dir}/index.js"
  content  = <<-EOT
const { Firestore, FieldValue } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client
const firestore = new Firestore();

// Register HTTP function
functions.http('visitCounter', async (req, res) => {
  // Enable CORS for browser requests
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    // Get page parameter or use default
    const page = req.query.page || req.body?.page || 'default';
    
    // Validate page parameter to prevent injection
    if (!/^[a-zA-Z0-9_-]+$/.test(page)) {
      return res.status(400).json({
        error: 'Invalid page parameter',
        message: 'Page parameter must contain only letters, numbers, hyphens, and underscores'
      });
    }
    
    // Reference to the counter document
    const counterDoc = firestore.collection('counters').doc(page);
    
    // Atomically increment the counter
    await counterDoc.set({
      count: FieldValue.increment(1),
      lastVisit: FieldValue.serverTimestamp()
    }, { merge: true });
    
    // Get the updated count
    const doc = await counterDoc.get();
    const currentCount = doc.exists ? doc.data().count : 1;
    
    // Return the current count
    res.json({
      page: page,
      visits: currentCount,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Error updating counter:', error);
    res.status(500).json({
      error: 'Failed to update counter',
      message: error.message
    });
  }
});
EOT
}

# Create a ZIP archive of the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = local.function_zip_path
  source_dir  = local.function_source_dir
  
  # Ensure source files are created before archiving
  depends_on = [
    local_file.package_json,
    local_file.function_code
  ]
}

# Create a Google Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_bucket" {
  name                        = "${var.project_id}-function-source-${local.resource_suffix}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy              = true
  
  labels = local.common_labels
  
  # Lifecycle configuration to manage old versions
  lifecycle_rule {
    condition {
      age = 7 # Delete objects older than 7 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Ensure APIs are enabled before creating bucket
  depends_on = [
    google_project_service.apis
  ]
}

# Upload the function source code to the bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Metadata for tracking
  metadata = {
    created-by = "terraform"
    recipe     = "visitor-counter-functions-firestore"
  }
}

# Create IAM service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa-${local.resource_suffix}"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the visitor counter Cloud Function to access Firestore"
  project      = var.project_id
  
  # Ensure APIs are enabled before creating service account
  depends_on = [
    google_project_service.apis
  ]
}

# Grant Firestore access to the service account
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant additional permissions for Cloud Function execution
resource "google_project_iam_member" "function_invoker" {
  count   = var.allow_unauthenticated ? 1 : 0
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "allUsers"
}

# Deploy the Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "visitor_counter" {
  name        = "${var.function_name}-${local.resource_suffix}"
  location    = var.region
  project     = var.project_id
  description = var.function_description
  
  labels = local.common_labels
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "visitCounter"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for the build process
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    # Runtime environment variables
    environment_variables = {
      FIRESTORE_PROJECT_ID = var.project_id
      NODE_ENV            = var.environment
    }
    
    # Configure ingress settings
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  # Ensure all dependencies are ready
  depends_on = [
    google_project_service.apis,
    google_firestore_database.visitor_counter_db,
    google_project_iam_member.function_firestore_user,
    google_storage_bucket_object.function_source
  ]
  
  # Timeout for function deployment
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Configure public access to the function if enabled
resource "google_cloud_run_service_iam_member" "public_access" {
  count    = var.allow_unauthenticated ? 1 : 0
  location = google_cloudfunctions2_function.visitor_counter.location
  project  = google_cloudfunctions2_function.visitor_counter.project
  service  = google_cloudfunctions2_function.visitor_counter.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create Firestore security rules (optional, for additional security)
resource "google_firestore_document" "security_rules" {
  project     = var.project_id
  database    = google_firestore_database.visitor_counter_db.name
  collection  = "metadata"
  document_id = "security_info"
  
  fields = jsonencode({
    created = {
      timestampValue = timestamp()
    }
    managed_by = {
      stringValue = "terraform"
    }
    purpose = {
      stringValue = "visitor counter security metadata"
    }
  })
  
  depends_on = [
    google_firestore_database.visitor_counter_db
  ]
}

# Output the function URL for easy access
output "function_url" {
  description = "URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.visitor_counter.service_config[0].uri
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.visitor_counter.name
}

output "firestore_database" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.visitor_counter_db.name
}

output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Deployment region"
  value       = var.region
}