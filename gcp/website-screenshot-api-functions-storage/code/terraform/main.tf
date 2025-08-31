# Website Screenshot API with Cloud Functions and Storage
# This configuration deploys a serverless screenshot API using Google Cloud Functions
# and Cloud Storage for reliable, scalable website screenshot generation

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  bucket_name = "${var.bucket_prefix}-${random_id.suffix.hex}"
  
  # Environment variables for the Cloud Function
  function_env_vars = merge({
    BUCKET_NAME = local.bucket_name
    NODE_ENV    = "production"
  }, var.environment_variables)
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    component = "screenshot-api"
    version   = "1.0"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com"
  ]) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for storing generated screenshots
resource "google_storage_bucket" "screenshots" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion
  deletion_protection = var.deletion_protection
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Public access to the storage bucket for screenshot URLs
resource "google_storage_bucket_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  bucket = google_storage_bucket.screenshots.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Screenshot Generator Function Service Account"
  description  = "Service account for the screenshot generation Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM binding for Cloud Function to write to Storage bucket
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.screenshots.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Additional IAM role for metadata access
resource "google_storage_bucket_iam_member" "function_metadata_access" {
  bucket = google_storage_bucket.screenshots.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = jsonencode({
      name        = "screenshot-api"
      version     = "1.0.0"
      main        = "index.js"
      scripts = {
        "gcp-build" = "node node_modules/puppeteer/install.mjs"
      }
      dependencies = {
        "@google-cloud/functions-framework" = "^4.0.0"
        "@google-cloud/storage"             = "^7.16.0"
        "puppeteer"                         = "^24.15.0"
      }
    })
    filename = "package.json"
  }
  
  source {
    content = <<-EOF
const {join} = require('path');

/**
 * @type {import("puppeteer").Configuration}
 */
module.exports = {
  // Changes the cache location for Puppeteer
  cacheDirectory: join(__dirname, '.cache', 'puppeteer'),
};
EOF
    filename = ".puppeteerrc.cjs"
  }
  
  source {
    content = <<-EOF
const functions = require('@google-cloud/functions-framework');
const puppeteer = require('puppeteer');
const {Storage} = require('@google-cloud/storage');

// Initialize Cloud Storage client
const storage = new Storage();
const bucketName = process.env.BUCKET_NAME;

functions.http('generateScreenshot', async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    // Extract URL from request
    const targetUrl = req.query.url || req.body?.url;
    
    if (!targetUrl) {
      return res.status(400).json({
        error: 'URL parameter is required'
      });
    }

    // Validate URL format
    try {
      new URL(targetUrl);
    } catch (urlError) {
      return res.status(400).json({
        error: 'Invalid URL format'
      });
    }

    console.log(`Taking screenshot of: $${targetUrl}`);

    // Launch browser with optimized settings
    const browser = await puppeteer.launch({
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--disable-gpu'
      ],
      headless: 'new'
    });

    const page = await browser.newPage();
    
    // Set viewport for consistent screenshots
    await page.setViewport({
      width: 1200,
      height: 800,
      deviceScaleFactor: 1
    });

    // Navigate and take screenshot
    await page.goto(targetUrl, {
      waitUntil: 'networkidle2',
      timeout: 30000
    });

    const screenshot = await page.screenshot({
      type: 'png',
      fullPage: false
    });

    await browser.close();

    // Generate unique filename
    const timestamp = Date.now();
    const filename = `screenshot-$${timestamp}.png`;

    // Upload to Cloud Storage
    const file = storage.bucket(bucketName).file(filename);
    
    await file.save(screenshot, {
      metadata: {
        contentType: 'image/png',
        metadata: {
          sourceUrl: targetUrl,
          generatedAt: new Date().toISOString()
        }
      }
    });

    // Return screenshot URL
    const publicUrl = `https://storage.googleapis.com/$${bucketName}/$${filename}`;
    
    res.json({
      success: true,
      screenshotUrl: publicUrl,
      filename: filename,
      sourceUrl: targetUrl
    });

  } catch (error) {
    console.error('Screenshot generation failed:', error);
    res.status(500).json({
      error: 'Screenshot generation failed',
      details: error.message
    });
  }
});
EOF
    filename = "index.js"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.bucket_name}-source"
  location                    = var.region
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Upload function source code to Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for screenshot generation
resource "google_cloudfunctions2_function" "screenshot_generator" {
  name     = var.function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = "nodejs20"
    entry_point = "generateScreenshot"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = local.function_env_vars
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.function_source
  ]
}

# Cloud Function IAM for public access
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.screenshot_generator.location
  cloud_function = google_cloudfunctions2_function.screenshot_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Run service IAM for public access (Cloud Functions v2 uses Cloud Run)
resource "google_cloud_run_service_iam_member" "public_access" {
  project  = var.project_id
  location = google_cloudfunctions2_function.screenshot_generator.location
  service  = google_cloudfunctions2_function.screenshot_generator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}