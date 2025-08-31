# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with consistent suffixes
  resource_suffix          = random_id.suffix.hex
  keyring_name            = "${var.resource_prefix}-keyring-${local.resource_suffix}"
  key_name                = "${var.resource_prefix}-encryption-key"
  vm_name                 = "${var.resource_prefix}-processor-${local.resource_suffix}"
  service_name            = "${var.resource_prefix}-service-${local.resource_suffix}"
  bucket_name             = "${var.resource_prefix}-data-${local.resource_suffix}"
  service_account_name    = "${var.resource_prefix}-processor"
  instance_group_name     = "${var.resource_prefix}-processors"
  health_check_name       = "${var.resource_prefix}-processor-health"
  backend_service_name    = "${var.resource_prefix}-backend"
  url_map_name           = "${var.resource_prefix}-map"
  ssl_cert_name          = "${var.resource_prefix}-cert"
  https_proxy_name       = "${var.resource_prefix}-proxy"
  forwarding_rule_name   = "${var.resource_prefix}-forwarding"
  firewall_rule_name     = "${var.resource_prefix}-allow-processor"
  
  # Common labels merged with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    recipe      = "secure-traffic-processing"
  })
  
  # APIs required for this infrastructure
  required_apis = [
    "compute.googleapis.com",
    "cloudkms.googleapis.com",
    "networkservices.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ==============================================================================
# CLOUD KMS RESOURCES
# ==============================================================================

# Cloud KMS Key Ring for traffic encryption keys
resource "google_kms_key_ring" "traffic_keyring" {
  name     = local.keyring_name
  location = var.region
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Primary encryption key for data protection with customer-managed encryption
resource "google_kms_crypto_key" "traffic_encryption_key" {
  name     = local.key_name
  key_ring = google_kms_key_ring.traffic_keyring.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = var.kms_key_rotation_period
  protection_level = var.kms_protection_level
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

# ==============================================================================
# IAM RESOURCES
# ==============================================================================

# Service account for Confidential VM with least privilege permissions
resource "google_service_account" "confidential_processor" {
  account_id   = local.service_account_name
  display_name = "Confidential Traffic Processor Service Account"
  description  = "Service account for Confidential VM traffic processing with KMS access"
  
  depends_on = [google_project_service.required_apis]
}

# Grant KMS encrypt/decrypt permissions to service account
resource "google_kms_crypto_key_iam_member" "kms_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.traffic_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.confidential_processor.email}"
}

# Grant storage admin permissions for secure data bucket
resource "google_storage_bucket_iam_member" "bucket_admin" {
  bucket = google_storage_bucket.secure_traffic_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.confidential_processor.email}"
}

# Grant monitoring writer permissions for observability
resource "google_project_iam_member" "monitoring_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.confidential_processor.email}"
}

# Grant logging writer permissions for audit trails
resource "google_project_iam_member" "logging_writer" {
  count = var.enable_logging ? 1 : 0
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.confidential_processor.email}"
}

# ==============================================================================
# COMPUTE ENGINE RESOURCES
# ==============================================================================

# Startup script for Confidential VM configuration
locals {
  startup_script = templatefile("${path.module}/scripts/startup.sh", {
    project_id     = var.project_id
    region         = var.region
    keyring_name   = local.keyring_name
    key_name       = local.key_name
    bucket_name    = local.bucket_name
    processor_port = var.traffic_processor_port
  })
}

# Confidential VM instance with AMD SEV-SNP protection
resource "google_compute_instance" "confidential_processor" {
  name         = local.vm_name
  machine_type = var.confidential_vm_machine_type
  zone         = var.zone
  
  # Enable Confidential Computing with AMD SEV-SNP
  confidential_instance_config {
    confidential_instance_type = var.confidential_compute_type
  }
  
  # Maintenance policy must be TERMINATE for Confidential VMs
  scheduling {
    on_host_maintenance = "TERMINATE"
  }
  
  # Boot disk configuration with encryption
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.confidential_vm_boot_disk_size
      type  = var.confidential_vm_boot_disk_type
      
      # Enable encryption with customer-managed key
      kms_key_self_link = google_kms_crypto_key.traffic_encryption_key.id
    }
    
    # Enable automatic deletion of boot disk
    auto_delete = true
  }
  
  # Network interface configuration
  network_interface {
    network = "default"
    
    # Assign external IP for demo purposes (consider removing for production)
    access_config {
      // Ephemeral public IP
    }
  }
  
  # Service account configuration with minimal permissions
  service_account {
    email  = google_service_account.confidential_processor.email
    scopes = ["cloud-platform"]
  }
  
  # Security tags for firewall rules
  tags = ["traffic-processor"]
  
  # Labels for resource organization
  labels = local.common_labels
  
  # Startup script for traffic processing engine installation
  metadata_startup_script = local.startup_script
  
  # Dependencies
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_member.kms_encrypter_decrypter,
    google_storage_bucket.secure_traffic_data
  ]
}

# ==============================================================================
# LOAD BALANCING RESOURCES
# ==============================================================================

# Unmanaged instance group for Confidential VM
resource "google_compute_instance_group" "traffic_processors" {
  name = local.instance_group_name
  zone = var.zone
  
  description = "Instance group for Confidential VM traffic processors"
  
  instances = [
    google_compute_instance.confidential_processor.id
  ]
  
  # Named ports for gRPC traffic processing service
  named_port {
    name = "grpc"
    port = var.traffic_processor_port
  }
}

# gRPC health check for traffic processing service
resource "google_compute_health_check" "traffic_processor_health" {
  name = local.health_check_name
  
  description         = "Health check for traffic processing service"
  timeout_sec         = var.health_check_timeout_seconds
  check_interval_sec  = var.health_check_check_interval_seconds
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  # gRPC health check configuration
  grpc_health_check {
    port_name = "grpc"
  }
  
  # Log health check results for debugging
  log_config {
    enable = var.enable_logging
  }
}

# Backend service for Confidential VM traffic processor
resource "google_compute_backend_service" "traffic_backend" {
  name = local.backend_service_name
  
  description                     = "Backend service for Confidential VM traffic processing"
  load_balancing_scheme          = "EXTERNAL_MANAGED"
  protocol                       = "GRPC"
  health_checks                  = [google_compute_health_check.traffic_processor_health.id]
  connection_draining_timeout_sec = 30
  
  # Backend configuration
  backend {
    group           = google_compute_instance_group.traffic_processors.id
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  # Security settings
  security_settings {
    client_tls_policy = null
    subject_alt_names = []
  }
  
  # Enable connection logging for security auditing
  log_config {
    enable      = var.enable_logging
    sample_rate = 1.0
  }
}

# URL map for load balancer routing
resource "google_compute_url_map" "secure_traffic_map" {
  name = local.url_map_name
  
  description     = "URL map for secure traffic processing load balancer"
  default_service = google_compute_backend_service.traffic_backend.id
  
  # Host and path rules can be added here for advanced routing
}

# Managed SSL certificate for HTTPS termination
resource "google_compute_managed_ssl_certificate" "secure_traffic_cert" {
  count = var.enable_ssl_certificate ? 1 : 0
  
  name = local.ssl_cert_name
  
  description = "Managed SSL certificate for secure traffic processing"
  
  managed {
    domains = var.ssl_certificate_domains
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS proxy for SSL termination
resource "google_compute_target_https_proxy" "secure_traffic_proxy" {
  count = var.enable_ssl_certificate ? 1 : 0
  
  name = local.https_proxy_name
  
  description = "HTTPS proxy for secure traffic processing"
  url_map     = google_compute_url_map.secure_traffic_map.id
  
  ssl_certificates = [
    google_compute_managed_ssl_certificate.secure_traffic_cert[0].id
  ]
  
  # Security settings
  ssl_policy = null  # Use default SSL policy
}

# HTTP proxy for non-SSL traffic (optional)
resource "google_compute_target_http_proxy" "secure_traffic_http_proxy" {
  count = var.enable_ssl_certificate ? 0 : 1
  
  name = "${local.https_proxy_name}-http"
  
  description = "HTTP proxy for secure traffic processing"
  url_map     = google_compute_url_map.secure_traffic_map.id
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "secure_traffic_forwarding" {
  name = local.forwarding_rule_name
  
  description           = "Global forwarding rule for secure traffic processing"
  port_range           = var.enable_ssl_certificate ? "443" : "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  
  target = var.enable_ssl_certificate ? (
    google_compute_target_https_proxy.secure_traffic_proxy[0].id
  ) : (
    google_compute_target_http_proxy.secure_traffic_http_proxy[0].id
  )
  
  labels = local.common_labels
}

# ==============================================================================
# NETWORK SECURITY RESOURCES
# ==============================================================================

# Firewall rule to allow traffic processor communication
resource "google_compute_firewall" "allow_traffic_processor" {
  name = local.firewall_rule_name
  
  description = "Allow traffic processor communication from authorized sources"
  network     = "default"
  direction   = "INGRESS"
  priority    = 1000
  
  # Allow TCP traffic on the processor port
  allow {
    protocol = "tcp"
    ports    = [tostring(var.traffic_processor_port)]
  }
  
  # Restrict access to authorized source ranges
  source_ranges = var.allowed_source_ranges
  
  # Apply to instances with traffic-processor tag
  target_tags = ["traffic-processor"]
}

# ==============================================================================
# STORAGE RESOURCES
# ==============================================================================

# Secure storage bucket with customer-managed encryption
resource "google_storage_bucket" "secure_traffic_data" {
  name     = local.bucket_name
  location = var.region
  
  # Storage class for cost optimization
  storage_class = var.storage_class
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Customer-managed encryption with Cloud KMS
  encryption {
    default_kms_key_name = google_kms_crypto_key.traffic_encryption_key.id
  }
  
  # Public access prevention for security
  public_access_prevention = "enforced"
  
  # Uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = true
  
  # Labels for resource organization
  labels = local.common_labels
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    
    content {
      # Move to COLDLINE storage after specified days
      condition {
        age = var.storage_lifecycle_coldline_age
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    
    content {
      # Delete objects after specified days
      condition {
        age = var.storage_lifecycle_delete_age
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Force destroy for testing environments (remove for production)
  force_destroy = var.environment != "prod"
  
  depends_on = [
    google_kms_crypto_key_iam_member.kms_encrypter_decrypter
  ]
}

# ==============================================================================
# MONITORING AND LOGGING RESOURCES
# ==============================================================================

# Monitoring notification channel for alerts (optional)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Email Notification Channel"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com"  # Replace with actual email
  }
  
  description = "Notification channel for secure traffic processing alerts"
}

# Monitoring alert policy for Confidential VM health
resource "google_monitoring_alert_policy" "vm_health" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Confidential VM Health Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "VM Instance Down"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${google_compute_instance.confidential_processor.instance_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.enable_monitoring ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
}