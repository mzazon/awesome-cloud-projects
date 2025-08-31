# Enable required APIs for the project
resource "google_project_service" "storage_api" {
  project = var.project_id
  service = "storage.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "dns_api" {
  project = var.project_id
  service = "dns.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  dns_zone_name = "${var.resource_prefix}-zone-${random_id.suffix.hex}"
  
  # Default website content
  default_index_html = <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to Cloud Website</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #4285F4; }
        .cloud-info { background: #f0f8ff; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Your Cloud Website!</h1>
        <div class="cloud-info">
            <p>This static website is hosted on Google Cloud Storage with:</p>
            <ul>
                <li>Automatic global content delivery</li>
                <li>99.999999999% (11 9's) data durability</li>
                <li>Pay-per-use pricing model</li>
                <li>Custom domain support</li>
            </ul>
        </div>
        <p>Deployed with Terraform on Google Cloud Platform</p>
    </div>
</body>
</html>
EOF

  default_error_html = <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        h1 { color: #EA4335; }
    </style>
</head>
<body>
    <h1>404 - Page Not Found</h1>
    <p>The page you're looking for doesn't exist.</p>
    <a href="/">Return to Homepage</a>
</body>
</html>
EOF

  # Determine content to use (custom or default)
  index_content = var.index_html_content != "" ? var.index_html_content : local.default_index_html
  error_content = var.error_html_content != "" ? var.error_html_content : local.default_error_html
}

# Create Cloud Storage bucket for static website hosting
# The bucket name must match the domain name for CNAME record compatibility
resource "google_storage_bucket" "website_bucket" {
  name                        = var.domain_name
  location                    = var.bucket_location
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  force_destroy              = true
  
  labels = var.labels

  # Enable website configuration
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  # Configure CORS if enabled
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = var.cors_origins
      method          = var.cors_methods
      response_header = ["*"]
      max_age_seconds = var.cache_control_max_age
    }
  }

  # Configure versioning if enabled
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Configure lifecycle rules if provided
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lifecycle_rule.value.action_storage_class
      }
      condition {
        age                        = lifecycle_rule.value.condition_age
        matches_storage_class      = lifecycle_rule.value.condition_matches_storage_class
      }
    }
  }

  depends_on = [google_project_service.storage_api]
}

# Configure bucket for public access if enabled
resource "google_storage_bucket_iam_member" "public_access" {
  count  = var.enable_public_access ? 1 : 0
  bucket = google_storage_bucket.website_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create index.html file
resource "google_storage_bucket_object" "index_html" {
  name   = "index.html"
  bucket = google_storage_bucket.website_bucket.name
  content = local.index_content
  content_type = "text/html"
  
  # Set cache control headers for optimal performance
  cache_control = "public, max-age=${var.cache_control_max_age}"
  
  # Add metadata
  metadata = {
    purpose = "website-index"
    created-by = "terraform"
  }
}

# Create 404.html error page
resource "google_storage_bucket_object" "error_html" {
  name   = "404.html"
  bucket = google_storage_bucket.website_bucket.name
  content = local.error_content
  content_type = "text/html"
  
  # Set cache control headers for optimal performance
  cache_control = "public, max-age=${var.cache_control_max_age}"
  
  # Add metadata
  metadata = {
    purpose = "website-error-page"
    created-by = "terraform"
  }
}

# Create Cloud DNS managed zone for the domain
resource "google_dns_managed_zone" "website_zone" {
  name        = local.dns_zone_name
  dns_name    = "${var.domain_name}."
  description = var.dns_zone_description
  visibility  = "public"
  
  labels = var.labels

  depends_on = [google_project_service.dns_api]
}

# Create CNAME record pointing to Cloud Storage
resource "google_dns_record_set" "website_cname" {
  name = google_dns_managed_zone.website_zone.dns_name
  type = "CNAME"
  ttl  = var.dns_record_ttl

  managed_zone = google_dns_managed_zone.website_zone.name
  
  # Point to Google Cloud Storage web serving endpoint
  rrdatas = ["c.storage.googleapis.com."]
}

# Optional: Create A record for the apex domain if using a subdomain
# This would require additional configuration for apex domain handling
resource "google_dns_record_set" "website_a_record" {
  count = length(split(".", var.domain_name)) == 2 ? 1 : 0  # Only for apex domains
  
  name = google_dns_managed_zone.website_zone.dns_name
  type = "A"
  ttl  = var.dns_record_ttl

  managed_zone = google_dns_managed_zone.website_zone.name
  
  # Google Cloud Storage IP addresses for A record (fallback)
  # Note: For production use, consider using Cloud Load Balancer
  rrdatas = [
    "216.239.32.21",
    "216.239.34.21",
    "216.239.36.21",
    "216.239.38.21"
  ]
}

# Create additional DNS records for common subdomains (optional)
resource "google_dns_record_set" "www_cname" {
  count = var.domain_name != "www.${var.domain_name}" ? 1 : 0
  
  name = "www.${google_dns_managed_zone.website_zone.dns_name}"
  type = "CNAME"
  ttl  = var.dns_record_ttl

  managed_zone = google_dns_managed_zone.website_zone.name
  
  # Point www subdomain to the main domain
  rrdatas = [var.domain_name]
}