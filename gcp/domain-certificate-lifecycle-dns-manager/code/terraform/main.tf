# Main Terraform configuration for GCP Domain and Certificate Lifecycle Management
# Recipe: Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  dns_zone_name     = var.dns_zone_name != "" ? var.dns_zone_name : "automation-zone-${random_id.suffix.hex}"
  certificate_name  = var.certificate_name != "" ? var.certificate_name : "ssl-cert-${random_id.suffix.hex}"
  function_name     = "cert-automation-${random_id.suffix.hex}"
  dns_function_name = "dns-update-${random_id.suffix.hex}"
  scheduler_job     = "cert-check-${random_id.suffix.hex}"
  daily_audit_job   = "daily-cert-audit-${random_id.suffix.hex}"
  
  # Certificate domains including primary and additional domains
  all_certificate_domains = concat([var.domain_name], var.certificate_domains)
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = "automation"
    component   = "certificate-management"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "dns.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud DNS zone for domain management
resource "google_dns_managed_zone" "automation_zone" {
  name        = local.dns_zone_name
  dns_name    = "${var.domain_name}."
  description = "Automated DNS zone for certificate management"
  
  visibility = "public"
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create service account for automation functions
resource "google_service_account" "cert_automation" {
  account_id   = var.service_account_name
  display_name = "Certificate Automation Service Account"
  description  = "Service account for DNS and certificate automation"

  depends_on = [google_project_service.required_apis]
}

# Grant DNS admin permissions to service account
resource "google_project_iam_member" "dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

# Grant Certificate Manager editor permissions to service account
resource "google_project_iam_member" "cert_manager_editor" {
  project = var.project_id
  role    = "roles/certificatemanager.editor"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

# Grant monitoring metric writer permissions to service account
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

# Grant logging writer permissions to service account
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

# Create Google-managed certificate
resource "google_certificate_manager_certificate" "ssl_certificate" {
  name        = local.certificate_name
  description = "Automated SSL certificate for ${var.domain_name}"
  location    = "global"
  
  managed {
    domains = local.all_certificate_domains
  }
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create certificate map for load balancer integration
resource "google_certificate_manager_certificate_map" "cert_map" {
  name        = "cert-map-${random_id.suffix.hex}"
  description = "Certificate map for automated SSL management"
  location    = "global"
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Add certificate to certificate map
resource "google_certificate_manager_certificate_map_entry" "cert_map_entry" {
  name         = var.domain_name
  description  = "Certificate map entry for ${var.domain_name}"
  location     = "global"
  map          = google_certificate_manager_certificate_map.cert_map.name
  certificates = [google_certificate_manager_certificate.ssl_certificate.id]
  hostname     = var.domain_name
}

# Create additional certificate map entries for additional domains
resource "google_certificate_manager_certificate_map_entry" "additional_cert_entries" {
  for_each = toset(var.certificate_domains)
  
  name         = replace(each.value, ".", "-")
  description  = "Certificate map entry for ${each.value}"
  location     = "global"
  map          = google_certificate_manager_certificate_map.cert_map.name
  certificates = [google_certificate_manager_certificate.ssl_certificate.id]
  hostname     = each.value
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-cert-automation-source-${random_id.suffix.hex}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create archive for certificate monitoring function
data "archive_file" "cert_monitoring_function" {
  type        = "zip"
  output_path = "/tmp/cert-monitoring-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "cert_monitoring_function_source" {
  name   = "cert-monitoring-function-${data.archive_file.cert_monitoring_function.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.cert_monitoring_function.output_path
}

# Deploy certificate monitoring Cloud Function
resource "google_cloudfunctions_function" "cert_monitoring" {
  name        = local.function_name
  description = "Automated certificate health monitoring and lifecycle management"
  runtime     = "python311"
  region      = var.region
  
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "check_certificates"
  service_account_email = google_service_account.cert_automation.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.cert_monitoring_function_source.name
  
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    GCP_PROJECT = var.project_id
    REGION      = var.region
  }
  
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.cert_manager_editor,
    google_project_iam_member.monitoring_writer
  ]
}

# Deploy DNS update Cloud Function
resource "google_cloudfunctions_function" "dns_update" {
  name        = local.dns_function_name
  description = "Automated DNS record management for certificate validation"
  runtime     = "python311"
  region      = var.region
  
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "update_dns_record"
  service_account_email = google_service_account.cert_automation.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.cert_monitoring_function_source.name
  
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    GCP_PROJECT = var.project_id
    REGION      = var.region
  }
  
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.dns_admin,
    google_project_iam_member.monitoring_writer
  ]
}

# Create Cloud Scheduler job for certificate monitoring
resource "google_cloud_scheduler_job" "cert_monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  name             = local.scheduler_job
  description      = "Automated certificate health monitoring"
  schedule         = var.monitoring_schedule
  time_zone        = "UTC"
  attempt_deadline = "60s"
  region           = var.region
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.cert_monitoring.https_trigger_url
  }

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler job for daily comprehensive audit
resource "google_cloud_scheduler_job" "daily_audit" {
  count = var.enable_monitoring ? 1 : 0
  
  name             = local.daily_audit_job
  description      = "Daily comprehensive certificate audit"
  schedule         = var.daily_audit_schedule
  time_zone        = "UTC"
  attempt_deadline = "60s"
  region           = var.region
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.cert_monitoring.https_trigger_url
  }

  depends_on = [google_project_service.required_apis]
}

# Create Application Load Balancer components (optional)
resource "google_compute_backend_service" "demo_backend" {
  count = var.create_load_balancer ? 1 : 0
  
  name        = "demo-backend-${random_id.suffix.hex}"
  description = "Demo backend service for certificate integration"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  
  health_checks = [google_compute_health_check.demo_health_check[0].id]

  depends_on = [google_project_service.required_apis]
}

# Create health check for backend service
resource "google_compute_health_check" "demo_health_check" {
  count = var.create_load_balancer ? 1 : 0
  
  name        = "demo-health-check-${random_id.suffix.hex}"
  description = "Health check for demo backend service"
  
  timeout_sec        = 5
  check_interval_sec = 10
  
  http_health_check {
    port = 80
    path = "/"
  }

  depends_on = [google_project_service.required_apis]
}

# Create URL map
resource "google_compute_url_map" "demo_url_map" {
  count = var.create_load_balancer ? 1 : 0
  
  name            = "demo-url-map-${random_id.suffix.hex}"
  description     = "Demo URL map for certificate integration"
  default_service = google_compute_backend_service.demo_backend[0].id

  depends_on = [google_project_service.required_apis]
}

# Create HTTPS proxy with certificate map
resource "google_compute_target_https_proxy" "demo_https_proxy" {
  count = var.create_load_balancer ? 1 : 0
  
  name             = "demo-https-proxy-${random_id.suffix.hex}"
  description      = "Demo HTTPS proxy with automated certificate management"
  url_map          = google_compute_url_map.demo_url_map[0].id
  certificate_map  = google_certificate_manager_certificate_map.cert_map.id

  depends_on = [google_project_service.required_apis]
}

# Create global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "demo_https_rule" {
  count = var.create_load_balancer ? 1 : 0
  
  name        = "demo-https-rule-${random_id.suffix.hex}"
  description = "Demo HTTPS forwarding rule"
  target      = google_compute_target_https_proxy.demo_https_proxy[0].id
  port_range  = "443"

  depends_on = [google_project_service.required_apis]
}

# Create A record pointing to load balancer
resource "google_dns_record_set" "a_record" {
  count = var.create_load_balancer ? 1 : 0
  
  name         = "${var.domain_name}."
  managed_zone = google_dns_managed_zone.automation_zone.name
  type         = "A"
  ttl          = var.dns_ttl
  
  rrdatas = [google_compute_global_forwarding_rule.demo_https_rule[0].ip_address]
}

# Create CNAME record for www subdomain
resource "google_dns_record_set" "www_cname" {
  count = var.enable_www_subdomain && var.create_load_balancer ? 1 : 0
  
  name         = "www.${var.domain_name}."
  managed_zone = google_dns_managed_zone.automation_zone.name
  type         = "CNAME"
  ttl          = var.dns_ttl
  
  rrdatas = ["${var.domain_name}."]
}

# Create Cloud Armor security policy (optional)
resource "google_compute_security_policy" "cloud_armor_policy" {
  count = var.enable_cloud_armor && var.create_load_balancer ? 1 : 0
  
  name        = "cloud-armor-policy-${random_id.suffix.hex}"
  description = "Cloud Armor security policy for certificate automation demo"
  
  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Allow all traffic"
  }
  
  rule {
    action   = "deny(403)"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny rule"
  }

  depends_on = [google_project_service.required_apis]
}

# Apply Cloud Armor policy to backend service
resource "google_compute_backend_service" "demo_backend_with_armor" {
  count = var.enable_cloud_armor && var.create_load_balancer ? 1 : 0
  
  name            = "demo-backend-armor-${random_id.suffix.hex}"
  description     = "Demo backend service with Cloud Armor protection"
  protocol        = "HTTP"
  port_name       = "http"
  timeout_sec     = 30
  security_policy = google_compute_security_policy.cloud_armor_policy[0].id
  
  health_checks = [google_compute_health_check.demo_health_check[0].id]

  depends_on = [google_project_service.required_apis]
}