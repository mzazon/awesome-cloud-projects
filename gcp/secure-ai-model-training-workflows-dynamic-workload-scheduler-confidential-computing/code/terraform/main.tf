# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current project information
data "google_project" "current" {}

data "google_client_config" "current" {}

locals {
  # Generate unique resource names
  resource_suffix = random_id.suffix.hex
  
  # Common resource names
  keyring_name               = "${var.resource_prefix}-keyring-${local.resource_suffix}"
  kms_key_name              = "${var.resource_prefix}-key"
  service_account_name      = "${var.resource_prefix}-sa-${local.resource_suffix}"
  bucket_name               = "${var.resource_prefix}-data-${local.resource_suffix}"
  reservation_name          = "${var.resource_prefix}-reservation-${local.resource_suffix}"
  instance_template_name    = "${var.resource_prefix}-template-${local.resource_suffix}"
  instance_name             = "${var.resource_prefix}-vm-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment     = var.environment
    project-id      = var.project_id
    resource-suffix = local.resource_suffix
    created-by      = "terraform"
    last-updated    = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Service APIs required for the solution
  required_apis = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "billingbudgets.googleapis.com"
  ]
}

#===============================================================================
# API ENABLEMENT
#===============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying infrastructure
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before proceeding
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

#===============================================================================
# NETWORK INFRASTRUCTURE
#===============================================================================

# VPC Network for secure AI training infrastructure
resource "google_compute_network" "training_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [time_sleep.wait_for_apis]
}

# Subnet for confidential computing instances
resource "google_compute_subnetwork" "training_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.training_network.id
  
  # Enable private Google access for secure API communication
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logs for security monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rules for confidential computing instances
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.resource_prefix}-allow-internal"
  network = google_compute_network.training_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.subnet_cidr]
  target_tags   = var.network_tags
}

# Firewall rule for SSH access (restricted to IAP)
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.resource_prefix}-allow-ssh-iap"
  network = google_compute_network.training_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  # Google Cloud IAP IP ranges
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.network_tags
}

# Firewall rule for secure HTTPS/API access
resource "google_compute_firewall" "allow_https" {
  name    = "${var.resource_prefix}-allow-https"
  network = google_compute_network.training_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.network_tags
}

#===============================================================================
# CLOUD KMS ENCRYPTION INFRASTRUCTURE
#===============================================================================

# KMS Keyring for training data encryption
resource "google_kms_key_ring" "training_keyring" {
  name     = local.keyring_name
  location = var.region
  
  depends_on = [time_sleep.wait_for_apis]
}

# KMS encryption key with automatic rotation
resource "google_kms_crypto_key" "training_key" {
  name            = local.kms_key_name
  key_ring        = google_kms_key_ring.training_keyring.id
  rotation_period = var.kms_key_rotation_period
  
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = var.kms_key_protection_level
  }
  
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

#===============================================================================
# SERVICE ACCOUNT AND IAM
#===============================================================================

# Service account for confidential computing instances
resource "google_service_account" "training_service_account" {
  account_id   = local.service_account_name
  display_name = "AI Training Confidential Computing Service Account"
  description  = "Service account for secure AI training in TEE environments"
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "training_sa_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/storage.objectAdmin",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/compute.instanceAdmin.v1"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.training_service_account.email}"
}

# KMS key access for service account
resource "google_kms_crypto_key_iam_member" "training_sa_kms_access" {
  crypto_key_id = google_kms_crypto_key.training_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.training_service_account.email}"
}

#===============================================================================
# CLOUD STORAGE FOR TRAINING DATA
#===============================================================================

# Encrypted Cloud Storage bucket for training data
resource "google_storage_bucket" "training_data_bucket" {
  name          = local.bucket_name
  location      = var.storage_bucket_location
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data lineage tracking
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Customer-managed encryption key
  encryption {
    default_kms_key_name = google_kms_crypto_key.training_key.id
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Access logging for compliance
  dynamic "logging" {
    for_each = var.enable_bucket_logging ? [1] : []
    content {
      log_bucket = google_storage_bucket.training_data_bucket.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_kms_crypto_key_iam_member.training_sa_kms_access]
}

# IAM binding for service account access to bucket
resource "google_storage_bucket_iam_member" "training_bucket_access" {
  bucket = google_storage_bucket.training_data_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.training_service_account.email}"
}

#===============================================================================
# DYNAMIC WORKLOAD SCHEDULER CONFIGURATION
#===============================================================================

# Compute reservation for Dynamic Workload Scheduler
resource "google_compute_reservation" "training_reservation" {
  count = var.enable_dynamic_workload_scheduler ? 1 : 0
  
  name = local.reservation_name
  zone = var.zone
  
  specific_reservation {
    count = var.vm_count
    instance_properties {
      machine_type = var.machine_type
      
      guest_accelerators {
        accelerator_type  = var.accelerator_type
        accelerator_count = var.accelerator_count
      }
    }
  }
  
  specific_reservation_required = true
}

# Instance template for confidential computing
resource "google_compute_instance_template" "confidential_training_template" {
  name         = local.instance_template_name
  machine_type = var.machine_type
  region       = var.region
  
  # Boot disk configuration
  disk {
    source_image = "projects/ml-images/global/images/family/deep-learning-vm"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type
    
    # Encrypt boot disk with customer-managed key
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.training_key.id
    }
  }
  
  # GPU configuration
  guest_accelerator {
    type  = var.accelerator_type
    count = var.accelerator_count
  }
  
  # Network configuration
  network_interface {
    network    = google_compute_network.training_network.id
    subnetwork = google_compute_subnetwork.training_subnet.id
    
    # No external IP for enhanced security
    # External access through Cloud NAT or IAP
  }
  
  # Service account configuration
  service_account {
    email  = google_service_account.training_service_account.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  # Security configuration
  confidential_instance_config {
    enable_confidential_compute = var.enable_confidential_compute
  }
  
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = var.enable_vtpm
    enable_integrity_monitoring = var.enable_integrity_monitoring
  }
  
  # Metadata and startup script
  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/startup-script.sh", {
      bucket_name      = google_storage_bucket.training_data_bucket.name
      service_account  = google_service_account.training_service_account.email
      kms_key_id      = google_kms_crypto_key.training_key.id
    })
  }
  
  tags   = var.network_tags
  labels = local.common_labels
  
  # Ensure GPU scheduling
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = false
  }
  
  depends_on = [
    google_project_iam_member.training_sa_roles,
    google_storage_bucket_iam_member.training_bucket_access
  ]
}

#===============================================================================
# CONFIDENTIAL COMPUTING INSTANCE
#===============================================================================

# Confidential computing instance for training
resource "google_compute_instance" "confidential_training_vm" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  
  # Use the instance template configuration
  source_instance_template = google_compute_instance_template.confidential_training_template.id
  
  # Reservation affinity for Dynamic Workload Scheduler
  dynamic "reservation_affinity" {
    for_each = var.enable_dynamic_workload_scheduler ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key    = "compute.googleapis.com/reservation-name"
        values = [google_compute_reservation.training_reservation[0].name]
      }
    }
  }
  
  labels = local.common_labels
  
  # Allow stopping for maintenance
  allow_stopping_for_update = true
}

#===============================================================================
# MONITORING AND ALERTING
#===============================================================================

# Cloud Monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring && var.monitoring_notification_email != "" ? 1 : 0
  
  display_name = "Secure AI Training Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.monitoring_notification_email
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Alert policy for confidential computing attestation failures
resource "google_monitoring_alert_policy" "attestation_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Confidential Computing Attestation Failure"
  combiner     = "OR"
  
  conditions {
    display_name = "TEE Attestation Failure"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/confidential_compute/attestation_failure\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.monitoring_notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  documentation {
    content = "Alert triggered when confidential computing attestation fails for secure AI training instances."
  }
}

# Alert policy for high GPU utilization
resource "google_monitoring_alert_policy" "gpu_utilization_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High GPU Utilization"
  combiner     = "OR"
  
  conditions {
    display_name = "GPU Utilization > 90%"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.9
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.monitoring_notification_email != "" ? [google_monitoring_notification_channel.email_notification[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  documentation {
    content = "Alert triggered when GPU utilization exceeds 90% for extended periods."
  }
}

#===============================================================================
# AUDIT LOGGING CONFIGURATION
#===============================================================================

# Data access audit logs for confidential computing
resource "google_project_iam_audit_config" "confidential_computing_audit" {
  count   = var.enable_audit_logging ? 1 : 0
  project = var.project_id
  service = "compute.googleapis.com"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Cloud Storage audit logs
resource "google_project_iam_audit_config" "storage_audit" {
  count   = var.enable_audit_logging ? 1 : 0
  project = var.project_id
  service = "storage.googleapis.com"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# KMS audit logs
resource "google_project_iam_audit_config" "kms_audit" {
  count   = var.enable_audit_logging ? 1 : 0
  project = var.project_id
  service = "cloudkms.googleapis.com"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

#===============================================================================
# BUDGET AND COST MANAGEMENT
#===============================================================================

# Data source for billing account
data "google_billing_account" "account" {
  billing_account = data.google_project.current.billing_account
}

# Budget alert for cost management
resource "google_billing_budget" "training_budget" {
  count = var.enable_budget_alerts ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
  display_name    = "Secure AI Training Budget - ${var.environment}"
  
  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    
    # Filter for AI training related services
    services = [
      "services/6F81-5844-456A", # Compute Engine
      "services/A1E8-BE35-7EBC", # Cloud Storage
      "services/95FF-2EF5-5EA1", # Cloud KMS
      "services/1B57-E421-B8E1"  # AI Platform
    ]
    
    labels = {
      "labels.purpose" = "secure-ai-training"
    }
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = var.budget_threshold_percent
    spend_basis       = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

#===============================================================================
# STARTUP SCRIPT FOR CONFIDENTIAL INSTANCES
#===============================================================================

# Generate startup script for confidential instances
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    bucket_name      = local.bucket_name
    service_account  = google_service_account.training_service_account.email
    kms_key_id      = google_kms_crypto_key.training_key.id
    project_id      = var.project_id
    region          = var.region
  })
  
  file_permission = "0755"
}

# Create startup script template
resource "local_file" "startup_script_template" {
  filename = "${path.module}/startup-script.tpl"
  content  = <<-EOF
#!/bin/bash

# Secure AI Training Startup Script
# This script configures the confidential computing environment for secure AI training

set -euo pipefail

# Logging setup
exec 1> >(logger -s -t startup-script-stdout)
exec 2> >(logger -s -t startup-script-stderr)

echo "Starting secure AI training environment configuration..."

# Update system packages
apt-get update
apt-get install -y \
    python3-pip \
    python3-venv \
    nvidia-utils-470 \
    google-cloud-sdk

# Configure Google Cloud authentication
gcloud auth activate-service-account ${service_account} --key-file=/dev/null

# Set up Python environment for training
python3 -m venv /opt/training-env
source /opt/training-env/bin/activate

# Install required Python packages
pip install --upgrade pip
pip install \
    torch \
    torchvision \
    tensorflow-gpu \
    scikit-learn \
    pandas \
    numpy \
    google-cloud-storage \
    google-cloud-aiplatform

# Create training directories
mkdir -p /opt/training/{data,models,logs,scripts}
chown -R training-user:training-user /opt/training

# Download training data from encrypted bucket
echo "Downloading training data from gs://${bucket_name}..."
gsutil -m cp -r gs://${bucket_name}/training/* /opt/training/data/

# Set up monitoring agent
curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
bash add-monitoring-agent-repo.sh --also-install

# Configure GPU monitoring
cat > /etc/google-cloud-ops-agent/config.yaml << 'EOCONFIG'
metrics:
  receivers:
    nvidia_gpu:
      type: nvidia_gpu
  service:
    pipelines:
      default_pipeline:
        receivers: [nvidia_gpu]
EOCONFIG

# Restart monitoring agent
systemctl restart google-cloud-ops-agent

# Verify confidential computing attestation
if command -v gcloud >/dev/null 2>&1; then
    echo "Verifying confidential computing attestation..."
    gcloud compute instances get-serial-port-output $(hostname) \
        --zone=${region}-a \
        --project=${project_id} || true
fi

# Create training environment validation script
cat > /opt/training/scripts/validate_environment.py << 'EOPY'
#!/usr/bin/env python3
import torch
import tensorflow as tf
import numpy as np
from google.cloud import storage
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_gpu():
    """Validate GPU availability and configuration."""
    if torch.cuda.is_available():
        logger.info(f"PyTorch CUDA available: {torch.cuda.device_count()} devices")
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            logger.info(f"GPU {i}: {props.name}, Memory: {props.total_memory/1e9:.1f}GB")
    
    if tf.config.list_physical_devices('GPU'):
        logger.info(f"TensorFlow GPUs: {len(tf.config.list_physical_devices('GPU'))}")
    
    return torch.cuda.is_available() and len(tf.config.list_physical_devices('GPU')) > 0

def validate_storage_access():
    """Validate access to encrypted training data."""
    try:
        client = storage.Client()
        bucket = client.bucket('${bucket_name}')
        blobs = list(bucket.list_blobs(prefix='training/', max_results=5))
        logger.info(f"Successfully accessed {len(blobs)} training files")
        return True
    except Exception as e:
        logger.error(f"Storage access failed: {e}")
        return False

def validate_confidential_computing():
    """Validate confidential computing environment."""
    try:
        with open('/sys/firmware/efi/efivars/StpAttest-bbe4e32a-9f5b-4a3f-8a78-1f0b08e1b5d0', 'rb') as f:
            attestation_data = f.read()
            logger.info("Confidential computing attestation data available")
            return True
    except FileNotFoundError:
        logger.warning("Confidential computing attestation not available")
        return False
    except Exception as e:
        logger.error(f"Confidential computing validation failed: {e}")
        return False

if __name__ == "__main__":
    gpu_ok = validate_gpu()
    storage_ok = validate_storage_access()
    cc_ok = validate_confidential_computing()
    
    if gpu_ok and storage_ok:
        logger.info("Environment validation successful - ready for secure training")
        exit(0)
    else:
        logger.error("Environment validation failed")
        exit(1)
EOPY

chmod +x /opt/training/scripts/validate_environment.py

# Run environment validation
python3 /opt/training/scripts/validate_environment.py

echo "Secure AI training environment configuration completed successfully"
EOF
}