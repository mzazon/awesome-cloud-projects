# ==============================================================================
# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# 
# This Terraform configuration deploys a complete certificate lifecycle management
# solution on Google Cloud Platform using:
# - Certificate Authority Service (Enterprise tier) for PKI infrastructure
# - Cloud Functions for automated certificate monitoring and renewal
# - Cloud Scheduler for proactive certificate monitoring
# - Secret Manager for secure certificate storage
# - IAM roles and service accounts for secure automation
# ==============================================================================

# ==============================================================================
# Data Sources and Local Values
# ==============================================================================

# Get current project information
data "google_project" "current" {}

# Get current client configuration
data "google_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  project_id = var.project_id != "" ? var.project_id : data.google_project.current.project_id
  
  # Resource naming with random suffix for uniqueness
  ca_pool_name          = "${var.ca_pool_name}-${random_id.suffix.hex}"
  root_ca_name          = "${var.root_ca_name}-${random_id.suffix.hex}"
  sub_ca_name           = "${var.sub_ca_name}-${random_id.suffix.hex}"
  monitor_function_name = "${var.monitor_function_name}-${random_id.suffix.hex}"
  renew_function_name   = "${var.renew_function_name}-${random_id.suffix.hex}"
  revoke_function_name  = "${var.revoke_function_name}-${random_id.suffix.hex}"
  scheduler_job_name    = "${var.scheduler_job_name}-${random_id.suffix.hex}"
  service_account_name  = "${var.service_account_name}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    solution    = "certificate-lifecycle-management"
    managed-by  = "terraform"
  })
}

# ==============================================================================
# Service Account for Certificate Automation
# ==============================================================================

# Service account for Cloud Functions to manage certificates
resource "google_service_account" "cert_automation" {
  account_id   = local.service_account_name
  display_name = "Certificate Automation Service Account"
  description  = "Service account for automated certificate lifecycle management"
  project      = local.project_id
}

# IAM role bindings for the service account
resource "google_project_iam_member" "cert_automation_privateca" {
  project = local.project_id
  role    = "roles/privateca.certificateManager"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

resource "google_project_iam_member" "cert_automation_secretmanager" {
  project = local.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

resource "google_project_iam_member" "cert_automation_logging" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

resource "google_project_iam_member" "cert_automation_monitoring" {
  project = local.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cert_automation.email}"
}

# ==============================================================================
# Certificate Authority Infrastructure
# ==============================================================================

# Certificate Authority Pool with Enterprise tier for full certificate lifecycle support
resource "google_privateca_ca_pool" "enterprise_ca_pool" {
  name     = local.ca_pool_name
  location = var.region
  tier     = "ENTERPRISE"
  project  = local.project_id
  
  # Publishing options for certificate distribution
  publishing_options {
    publish_ca_cert = true
    publish_crl     = true
    encoding_format = "PEM"
  }
  
  # Issuance policy to control certificate properties
  issuance_policy {
    # Allow both CSR-based and config-based issuance
    allowed_issuance_modes {
      allow_csr_based_issuance    = true
      allow_config_based_issuance = true
    }
    
    # Allow RSA and ECDSA key types
    allowed_key_types {
      rsa {
        min_modulus_size = 2048
        max_modulus_size = 4096
      }
    }
    
    allowed_key_types {
      elliptic_curve {
        signature_algorithm = "ECDSA_P256"
      }
    }
    
    # Maximum certificate lifetime
    maximum_lifetime = "${var.max_cert_lifetime_days * 24}h"
    
    # Identity constraints
    identity_constraints {
      allow_subject_passthrough           = true
      allow_subject_alt_names_passthrough = true
      
      cel_expression {
        expression  = "subject_alt_names.all(san, san.type == DNS || san.type == EMAIL)"
        title       = "DNS and Email SANs only"
        description = "Only DNS and Email Subject Alternative Names are allowed"
      }
    }
    
    # Baseline values for certificates
    baseline_values {
      ca_options {
        is_ca                 = false
        max_issuer_path_length = 0
      }
      
      key_usage {
        base_key_usage {
          digital_signature  = true
          key_encipherment   = true
          content_commitment = false
          data_encipherment  = false
          key_agreement      = false
          cert_sign          = false
          crl_sign           = false
        }
        
        extended_key_usage {
          server_auth = true
          client_auth = true
        }
      }
    }
  }
  
  labels = local.common_labels
}

# Root Certificate Authority (trust anchor)
resource "google_privateca_certificate_authority" "root_ca" {
  pool                     = google_privateca_ca_pool.enterprise_ca_pool.name
  certificate_authority_id = local.root_ca_name
  location                 = var.region
  project                  = local.project_id
  type                     = "SELF_SIGNED"
  
  config {
    subject_config {
      subject {
        organization  = var.organization_name
        country_code  = var.country_code
        common_name   = "${var.organization_name} Root CA"
      }
    }
    
    x509_config {
      ca_options {
        is_ca                 = true
        max_issuer_path_length = 2
      }
      
      key_usage {
        base_key_usage {
          cert_sign    = true
          crl_sign     = true
        }
        
        extended_key_usage {}
      }
    }
  }
  
  # Use RSA 4096-bit keys for long-term security
  key_spec {
    algorithm = "RSA_PKCS1_4096_SHA256"
  }
  
  # 10-year validity for root CA
  lifetime = "${var.root_ca_lifetime_years * 365 * 24}h"
  
  labels = local.common_labels
}

# Enable the root CA
resource "google_privateca_certificate_authority" "root_ca_enable" {
  pool                     = google_privateca_ca_pool.enterprise_ca_pool.name
  certificate_authority_id = google_privateca_certificate_authority.root_ca.certificate_authority_id
  location                 = var.region
  project                  = local.project_id
  state                    = "ENABLED"
  
  depends_on = [google_privateca_certificate_authority.root_ca]
  
  config {
    subject_config {
      subject {
        organization  = var.organization_name
        country_code  = var.country_code
        common_name   = "${var.organization_name} Root CA"
      }
    }
    
    x509_config {
      ca_options {
        is_ca                 = true
        max_issuer_path_length = 2
      }
      
      key_usage {
        base_key_usage {
          cert_sign    = true
          crl_sign     = true
        }
        
        extended_key_usage {}
      }
    }
  }
  
  key_spec {
    algorithm = "RSA_PKCS1_4096_SHA256"
  }
  
  lifetime = "${var.root_ca_lifetime_years * 365 * 24}h"
  labels   = local.common_labels
}

# Subordinate Certificate Authority for operational certificate issuance
resource "google_privateca_certificate_authority" "sub_ca" {
  pool                     = google_privateca_ca_pool.enterprise_ca_pool.name
  certificate_authority_id = local.sub_ca_name
  location                 = var.region
  project                  = local.project_id
  type                     = "SUBORDINATE"
  
  config {
    subject_config {
      subject {
        organization          = var.organization_name
        organizational_unit   = "Operations"
        country_code          = var.country_code
        common_name           = "${var.organization_name} Subordinate CA"
      }
    }
    
    x509_config {
      ca_options {
        is_ca                 = true
        max_issuer_path_length = 0
      }
      
      key_usage {
        base_key_usage {
          cert_sign    = true
          crl_sign     = true
        }
        
        extended_key_usage {}
      }
    }
  }
  
  # Use RSA 2048-bit keys for operational CA
  key_spec {
    algorithm = "RSA_PKCS1_2048_SHA256"
  }
  
  # 5-year validity for subordinate CA
  lifetime = "${var.sub_ca_lifetime_years * 365 * 24}h"
  
  # Subordinate CA is issued by the root CA
  subordinate_config {
    certificate_authority = google_privateca_certificate_authority.root_ca_enable.name
  }
  
  labels = local.common_labels
  
  depends_on = [google_privateca_certificate_authority.root_ca_enable]
}

# Enable the subordinate CA
resource "google_privateca_certificate_authority" "sub_ca_enable" {
  pool                     = google_privateca_ca_pool.enterprise_ca_pool.name
  certificate_authority_id = google_privateca_certificate_authority.sub_ca.certificate_authority_id
  location                 = var.region
  project                  = local.project_id
  state                    = "ENABLED"
  
  depends_on = [google_privateca_certificate_authority.sub_ca]
  
  config {
    subject_config {
      subject {
        organization          = var.organization_name
        organizational_unit   = "Operations"
        country_code          = var.country_code
        common_name           = "${var.organization_name} Subordinate CA"
      }
    }
    
    x509_config {
      ca_options {
        is_ca                 = true
        max_issuer_path_length = 0
      }
      
      key_usage {
        base_key_usage {
          cert_sign    = true
          crl_sign     = true
        }
        
        extended_key_usage {}
      }
    }
  }
  
  key_spec {
    algorithm = "RSA_PKCS1_2048_SHA256"
  }
  
  lifetime = "${var.sub_ca_lifetime_years * 365 * 24}h"
  
  subordinate_config {
    certificate_authority = google_privateca_certificate_authority.root_ca_enable.name
  }
  
  labels = local.common_labels
}

# ==============================================================================
# Certificate Template for Standardized Issuance
# ==============================================================================

# Certificate template for web server certificates
resource "google_privateca_certificate_template" "web_server_template" {
  name        = "web-server-template-${random_id.suffix.hex}"
  location    = var.region
  project     = local.project_id
  description = "Standard template for web server certificates"
  
  predefined_values {
    ca_options {
      is_ca = false
    }
    
    key_usage {
      base_key_usage {
        digital_signature = true
        key_encipherment  = true
      }
      
      extended_key_usage {
        server_auth = true
        client_auth = true
      }
    }
    
    policy_ids {
      object_id_path = [1, 3, 6, 1, 4, 1, 11129, 2, 5, 2]
    }
  }
  
  identity_constraints {
    allow_subject_passthrough           = true
    allow_subject_alt_names_passthrough = true
    
    cel_expression {
      expression  = "subject_alt_names.all(san, san.type == DNS)"
      title       = "DNS SANs only"
      description = "Only DNS Subject Alternative Names are allowed"
    }
  }
  
  passthrough_extensions {
    known_extensions = ["SUBJECT_ALT_NAME"]
    
    additional_extensions {
      object_id_path = [2, 5, 29, 17]
    }
  }
  
  labels = local.common_labels
}

# ==============================================================================
# Cloud Storage Bucket for Function Source Code
# ==============================================================================

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.project_id}-cert-functions-${random_id.suffix.hex}"
  location = var.region
  project  = local.project_id
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

# ==============================================================================
# Cloud Functions for Certificate Automation
# ==============================================================================

# ZIP archive for certificate monitoring function
data "archive_file" "monitor_function_zip" {
  type        = "zip"
  output_path = "/tmp/monitor_function.zip"
  source {
    content = templatefile("${path.module}/functions/monitor_function.py.tpl", {
      project_id             = local.project_id
      ca_pool_name          = local.ca_pool_name
      region                = var.region
      renewal_threshold_days = var.renewal_threshold_days
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload monitoring function source to storage
resource "google_storage_bucket_object" "monitor_function_source" {
  name   = "monitor_function_${data.archive_file.monitor_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.monitor_function_zip.output_path
}

# Certificate monitoring Cloud Function
resource "google_cloudfunctions2_function" "cert_monitor" {
  name        = local.monitor_function_name
  location    = var.region
  project     = local.project_id
  description = "Monitor certificates for expiration and trigger renewal"
  
  build_config {
    runtime     = "python39"
    entry_point = "certificate_monitor"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.monitor_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 540
    service_account_email = google_service_account.cert_automation.email
    
    environment_variables = {
      PROJECT_ID              = local.project_id
      CA_POOL_NAME           = local.ca_pool_name
      REGION                 = var.region
      RENEWAL_THRESHOLD_DAYS = var.renewal_threshold_days
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_iam_member.cert_automation_privateca,
    google_project_iam_member.cert_automation_secretmanager,
    google_project_iam_member.cert_automation_logging
  ]
}

# ZIP archive for certificate renewal function
data "archive_file" "renewal_function_zip" {
  type        = "zip"
  output_path = "/tmp/renewal_function.zip"
  source {
    content = templatefile("${path.module}/functions/renewal_function.py.tpl", {
      project_id   = local.project_id
      ca_pool_name = local.ca_pool_name
      sub_ca_name  = local.sub_ca_name
      region       = var.region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload renewal function source to storage
resource "google_storage_bucket_object" "renewal_function_source" {
  name   = "renewal_function_${data.archive_file.renewal_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.renewal_function_zip.output_path
}

# Certificate renewal Cloud Function
resource "google_cloudfunctions2_function" "cert_renewal" {
  name        = local.renew_function_name
  location    = var.region
  project     = local.project_id
  description = "Renew expiring certificates using Certificate Authority Service"
  
  build_config {
    runtime     = "python39"
    entry_point = "certificate_renewal"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.renewal_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "512M"
    timeout_seconds       = 540
    service_account_email = google_service_account.cert_automation.email
    
    environment_variables = {
      PROJECT_ID   = local.project_id
      CA_POOL_NAME = local.ca_pool_name
      SUB_CA_NAME  = local.sub_ca_name
      REGION       = var.region
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_iam_member.cert_automation_privateca,
    google_project_iam_member.cert_automation_secretmanager,
    google_project_iam_member.cert_automation_logging
  ]
}

# ZIP archive for certificate revocation function
data "archive_file" "revocation_function_zip" {
  type        = "zip"
  output_path = "/tmp/revocation_function.zip"
  source {
    content = templatefile("${path.module}/functions/revocation_function.py.tpl", {
      project_id   = local.project_id
      ca_pool_name = local.ca_pool_name
      sub_ca_name  = local.sub_ca_name
      region       = var.region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload revocation function source to storage
resource "google_storage_bucket_object" "revocation_function_source" {
  name   = "revocation_function_${data.archive_file.revocation_function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.revocation_function_zip.output_path
}

# Certificate revocation Cloud Function
resource "google_cloudfunctions2_function" "cert_revocation" {
  name        = local.revoke_function_name
  location    = var.region
  project     = local.project_id
  description = "Revoke compromised certificates and update CRL"
  
  build_config {
    runtime     = "python39"
    entry_point = "certificate_revocation"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.revocation_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 540
    service_account_email = google_service_account.cert_automation.email
    
    environment_variables = {
      PROJECT_ID   = local.project_id
      CA_POOL_NAME = local.ca_pool_name
      SUB_CA_NAME  = local.sub_ca_name
      REGION       = var.region
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_iam_member.cert_automation_privateca,
    google_project_iam_member.cert_automation_secretmanager,
    google_project_iam_member.cert_automation_logging
  ]
}

# ==============================================================================
# Cloud Scheduler for Automated Certificate Monitoring
# ==============================================================================

# Cloud Scheduler job for regular certificate monitoring
resource "google_cloud_scheduler_job" "cert_monitoring" {
  name             = local.scheduler_job_name
  region           = var.region
  project          = local.project_id
  description      = "Daily certificate expiration monitoring"
  schedule         = var.monitoring_schedule
  time_zone        = var.time_zone
  attempt_deadline = "320s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.cert_monitor.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      source = "scheduler"
      action = "monitor"
    }))
    
    oidc_token {
      service_account_email = google_service_account.cert_automation.email
      audience              = google_cloudfunctions2_function.cert_monitor.service_config[0].uri
    }
  }
  
  depends_on = [google_cloudfunctions2_function.cert_monitor]
}

# ==============================================================================
# Monitoring and Alerting
# ==============================================================================

# Alerting policy for certificate monitoring function errors
resource "google_monitoring_alert_policy" "cert_monitor_errors" {
  display_name = "Certificate Monitor Function Errors"
  project      = local.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Certificate Monitor Function Error Rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.monitor_function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  documentation {
    content   = "Alert when the certificate monitoring function encounters errors"
    mime_type = "text/markdown"
  }
  
  enabled = true
}

# Alerting policy for certificate renewal function errors
resource "google_monitoring_alert_policy" "cert_renewal_errors" {
  display_name = "Certificate Renewal Function Errors"
  project      = local.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Certificate Renewal Function Error Rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.renew_function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  documentation {
    content   = "Alert when the certificate renewal function encounters errors"
    mime_type = "text/markdown"
  }
  
  enabled = true
}