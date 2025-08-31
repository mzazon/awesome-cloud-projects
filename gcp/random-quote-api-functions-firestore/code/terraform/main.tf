# =============================================================================
# Random Quote API with Cloud Functions and Firestore - Terraform Configuration
# =============================================================================
# This Terraform configuration deploys a serverless REST API using Google Cloud
# Functions for HTTP handling and Firestore as a NoSQL database for quote storage.
# The solution provides automatic scaling, built-in security, and pay-per-use pricing.

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
# Define local values for resource naming and configuration
locals {
  # Generate random suffix for unique resource naming
  random_suffix = substr(md5(timestamp()), 0, 8)
  
  # Resource naming with consistent prefix
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common labels applied to all resources
  common_labels = {
    project     = var.project_name
    environment = var.environment
    created_by  = "terraform"
    recipe      = "random-quote-api-functions-firestore"
  }
  
  # Cloud Function source archive path
  function_source_dir = "${path.module}/function-source"
  function_zip_path   = "${path.module}/function-source.zip"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
# Get current project information for resource references
data "google_project" "current" {}

# Get current client configuration for zone information
data "google_client_config" "current" {}

# -----------------------------------------------------------------------------
# Random Resources
# -----------------------------------------------------------------------------
# Generate random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# Google Cloud APIs
# -----------------------------------------------------------------------------
# Enable Cloud Functions API
resource "google_project_service" "cloud_functions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
  
  # Prevent API from being disabled when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Firestore API
resource "google_project_service" "firestore" {
  project = var.project_id
  service = "firestore.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Build API (required for Cloud Functions deployment)
resource "google_project_service" "cloud_build" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Enable Cloud Resource Manager API
resource "google_project_service" "resource_manager" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# -----------------------------------------------------------------------------
# Firestore Database
# -----------------------------------------------------------------------------
# Create Firestore database in Native mode for document storage
resource "google_firestore_database" "quotes_database" {
  project     = var.project_id
  name        = var.firestore_database_id
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  # Deletion protection for production environments
  deletion_policy = var.environment == "production" ? "DELETE_PROTECTION_ENABLED" : "ABANDON"
  
  # Ensure APIs are enabled before creating database
  depends_on = [
    google_project_service.firestore,
    google_project_service.resource_manager
  ]
}

# -----------------------------------------------------------------------------
# Cloud Storage Bucket for Function Source Code
# -----------------------------------------------------------------------------
# Create storage bucket for Cloud Function source code deployment
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle policy to manage storage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Apply common labels
  labels = local.common_labels
  
  # Ensure APIs are enabled
  depends_on = [google_project_service.cloud_functions]
}

# -----------------------------------------------------------------------------
# Cloud Function Source Code
# -----------------------------------------------------------------------------
# Create the function source directory structure
resource "local_file" "package_json" {
  filename = "${local.function_source_dir}/package.json"
  content = jsonencode({
    name = "random-quote-api"
    version = "1.0.0"
    main = "index.js"
    dependencies = {
      "@google-cloud/firestore" = "^7.1.0"
      "@google-cloud/functions-framework" = "^3.3.0"
    }
  })
  
  # Create directory if it doesn't exist
  provisioner "local-exec" {
    command = "mkdir -p ${dirname(self.filename)}"
  }
}

# Create the main function implementation
resource "local_file" "function_code" {
  filename = "${local.function_source_dir}/index.js"
  content = <<-EOF
const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client with automatic project detection
const firestore = new Firestore({
  databaseId: process.env.DATABASE_ID || '${var.firestore_database_id}'
});

// HTTP Cloud Function that responds to GET requests
functions.http('randomQuote', async (req, res) => {
  // Set CORS headers for web browser compatibility
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET');
  
  try {
    // Query all documents from the 'quotes' collection
    const quotesRef = firestore.collection('quotes');
    const snapshot = await quotesRef.get();
    
    if (snapshot.empty) {
      return res.status(404).json({ 
        error: 'No quotes found in database' 
      });
    }
    
    // Select a random document from the collection
    const quotes = snapshot.docs;
    const randomIndex = Math.floor(Math.random() * quotes.length);
    const randomQuote = quotes[randomIndex];
    
    // Return the quote data with metadata
    const quoteData = randomQuote.data();
    res.status(200).json({
      id: randomQuote.id,
      quote: quoteData.text,
      author: quoteData.author,
      category: quoteData.category || 'general',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Error fetching quote:', error);
    res.status(500).json({ 
      error: 'Internal server error' 
    });
  }
});
EOF
  
  depends_on = [local_file.package_json]
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = local.function_zip_path
  
  depends_on = [
    local_file.package_json,
    local_file.function_code
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Content type for ZIP files
  content_type = "application/zip"
}

# -----------------------------------------------------------------------------
# Cloud Function
# -----------------------------------------------------------------------------
# Deploy the Cloud Function for the Random Quote API
resource "google_cloudfunctions_function" "random_quote_api" {
  name    = var.function_name
  project = var.project_id
  region  = var.region
  
  # Function runtime and configuration
  runtime               = "nodejs20"
  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  entry_point          = "randomQuote"
  max_instances        = var.function_max_instances
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    http_trigger {
      # Security level - allow unauthenticated access for public API
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Environment variables for function configuration
  environment_variables = {
    DATABASE_ID = google_firestore_database.quotes_database.name
    NODE_ENV    = var.environment
  }
  
  # Apply common labels
  labels = merge(local.common_labels, {
    function_type = "http"
    api_type     = "rest"
  })
  
  # Ensure APIs and dependencies are ready
  depends_on = [
    google_project_service.cloud_functions,
    google_project_service.cloud_build,
    google_firestore_database.quotes_database,
    google_storage_bucket_object.function_source
  ]
}

# -----------------------------------------------------------------------------
# IAM Configuration
# -----------------------------------------------------------------------------
# Allow public access to the Cloud Function (if enabled)
resource "google_cloudfunctions_function_iam_member" "public_access" {
  count = var.allow_public_access ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.random_quote_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Grant the Cloud Function service account access to Firestore
resource "google_project_iam_member" "function_firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  
  depends_on = [google_cloudfunctions_function.random_quote_api]
}

# -----------------------------------------------------------------------------
# Sample Data Population (Optional)
# -----------------------------------------------------------------------------
# Create local script for populating Firestore with sample quotes
resource "local_file" "populate_quotes_script" {
  count    = var.populate_sample_data ? 1 : 0
  filename = "${local.function_source_dir}/populate-quotes.js"
  content = <<-EOF
const { Firestore } = require('@google-cloud/firestore');

const firestore = new Firestore({
  databaseId: process.env.DATABASE_ID || '${var.firestore_database_id}'
});

const sampleQuotes = [
  {
    text: "The only way to do great work is to love what you do.",
    author: "Steve Jobs",
    category: "motivation"
  },
  {
    text: "Innovation distinguishes between a leader and a follower.",
    author: "Steve Jobs", 
    category: "innovation"
  },
  {
    text: "Life is what happens to you while you're busy making other plans.",
    author: "John Lennon",
    category: "life"
  },
  {
    text: "The future belongs to those who believe in the beauty of their dreams.",
    author: "Eleanor Roosevelt",
    category: "inspiration"
  },
  {
    text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
    author: "Winston Churchill",
    category: "perseverance"
  }
];

async function populateQuotes() {
  const quotesCollection = firestore.collection('quotes');
  
  for (const quote of sampleQuotes) {
    await quotesCollection.add(quote);
    console.log(`Added quote: "$${quote.text.substring(0, 30)}..."`);
  }
  
  console.log('✅ Sample quotes added to Firestore');
}

populateQuotes().catch(console.error);
EOF
  
  depends_on = [google_firestore_database.quotes_database]
}

# Execute the sample data population script (if enabled)
resource "null_resource" "populate_sample_data" {
  count = var.populate_sample_data ? 1 : 0
  
  provisioner "local-exec" {
    command = <<-EOT
      cd ${local.function_source_dir}
      npm install
      DATABASE_ID=${google_firestore_database.quotes_database.name} \
      GOOGLE_CLOUD_PROJECT=${var.project_id} \
      node populate-quotes.js
    EOT
  }
  
  depends_on = [
    local_file.populate_quotes_script[0],
    google_firestore_database.quotes_database,
    google_cloudfunctions_function.random_quote_api
  ]
  
  # Trigger re-execution if the database changes
  triggers = {
    database_id = google_firestore_database.quotes_database.name
    script_hash = local_file.populate_quotes_script[0].content_md5
  }
}

# -----------------------------------------------------------------------------
# Cleanup Resources
# -----------------------------------------------------------------------------
# Clean up local files after deployment (optional)
resource "null_resource" "cleanup_local_files" {
  count = var.cleanup_local_files ? 1 : 0
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf ${local.function_source_dir}
      rm -f ${local.function_zip_path}
    EOT
  }
  
  depends_on = [google_cloudfunctions_function.random_quote_api]
}