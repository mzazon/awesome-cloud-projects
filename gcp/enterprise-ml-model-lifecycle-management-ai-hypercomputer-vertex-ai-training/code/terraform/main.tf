# Enterprise ML Model Lifecycle Management Infrastructure
# This file contains the main infrastructure resources for the enterprise ML solution
# including Cloud Workstations, AI Hypercomputer, Vertex AI, and supporting services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for common configurations
locals {
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    "environment" = var.environment
    "terraform"   = "true"
    "recipe"      = "enterprise-ml-lifecycle"
  })
  
  # Resource naming with prefix and suffix
  resource_suffix = random_id.suffix.hex
  
  # Compute unique resource names
  workstation_cluster_name = "${var.resource_prefix}-workstations-${local.resource_suffix}"
  workstation_config_name  = "${var.resource_prefix}-config-${local.resource_suffix}"
  bucket_name             = "${var.resource_prefix}-artifacts-${var.project_id}-${local.resource_suffix}"
  dataset_name            = "${var.resource_prefix}_experiments_${local.resource_suffix}"
  registry_name           = "${var.resource_prefix}-containers-${local.resource_suffix}"
  
  # Network names
  network_name = "${var.resource_prefix}-network-${local.resource_suffix}"
  subnet_name  = "${var.resource_prefix}-subnet-${local.resource_suffix}"
  
  # Service account names
  workstation_sa_name = "${var.resource_prefix}-workstation-sa-${local.resource_suffix}"
  training_sa_name    = "${var.resource_prefix}-training-sa-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "workstations.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbilling.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "tpu.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Don't disable the service on destroy
  disable_on_destroy = false
}

# Create VPC network for ML infrastructure
resource "google_compute_network" "ml_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  mtu                     = 1460
  project                 = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for ML workloads
resource "google_compute_subnetwork" "ml_subnet" {
  name          = local.subnet_name
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.ml_network.id
  project       = var.project_id
  
  # Enable private Google access for accessing Google services
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
  
  # Secondary IP ranges for pods and services (if needed for GKE)
  secondary_ip_range {
    range_name    = "ml-pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "ml-services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Firewall rule to allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.network_name}-allow-internal"
  network = google_compute_network.ml_network.name
  project = var.project_id
  
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
  
  source_ranges = ["10.0.0.0/16"]
  
  depends_on = [google_project_service.required_apis]
}

# Firewall rule to allow SSH access
resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.network_name}-allow-ssh"
  network = google_compute_network.ml_network.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-enabled"]
  
  depends_on = [google_project_service.required_apis]
}

# Firewall rule to allow ML-specific ports
resource "google_compute_firewall" "allow_ml_ports" {
  name    = "${local.network_name}-allow-ml-ports"
  network = google_compute_network.ml_network.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "8888", "6006", "3000", "5000", "8000"]
  }
  
  source_ranges = ["10.0.0.0/16"]
  target_tags   = ["ml-workstation", "ml-training"]
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Workstations
resource "google_service_account" "workstation_sa" {
  account_id   = local.workstation_sa_name
  display_name = "Cloud Workstations Service Account"
  description  = "Service account for Cloud Workstations ML development environment"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Service account for training workloads
resource "google_service_account" "training_sa" {
  account_id   = local.training_sa_name
  display_name = "ML Training Service Account"
  description  = "Service account for ML training workloads"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for workstation service account
resource "google_project_iam_member" "workstation_sa_roles" {
  for_each = toset(var.workstation_service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

# IAM roles for training service account
resource "google_project_iam_member" "training_sa_roles" {
  for_each = toset(var.training_service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.training_sa.email}"
}

# Cloud Storage bucket for ML artifacts
resource "google_storage_bucket" "ml_artifacts" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Enable versioning for model artifacts
  versioning {
    enabled = var.enable_storage_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days * 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable logging for compliance
  logging {
    log_bucket = google_storage_bucket.ml_artifacts.name
    log_object_prefix = "access_logs/"
  }
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for ML experiments
resource "google_bigquery_dataset" "ml_experiments" {
  dataset_id    = local.dataset_name
  friendly_name = "ML Experiments Dataset"
  description   = "Dataset for storing ML experiment data and results"
  location      = var.bigquery_dataset_location
  project       = var.project_id
  
  # Set default table expiration
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
  
  # Enable delete protection for production
  delete_contents_on_destroy = var.environment == "dev" ? true : false
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Artifact Registry repository for ML containers
resource "google_artifact_registry_repository" "ml_containers" {
  repository_id = local.registry_name
  format        = var.artifact_registry_format
  location      = var.region
  project       = var.project_id
  
  description = "Container registry for ML training images"
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Workstations cluster
resource "google_workstations_cluster" "ml_workstations" {
  workstation_cluster_id = local.workstation_cluster_name
  location              = var.region
  project               = var.project_id
  
  network    = google_compute_network.ml_network.id
  subnetwork = google_compute_subnetwork.ml_subnet.id
  
  # Enable private cluster endpoint for security
  private_cluster_config {
    enable_private_endpoint = true
    cluster_hostname        = "${local.workstation_cluster_name}.${var.region}.cloudworkstations.dev"
  }
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Workstations configuration
resource "google_workstations_workstation_config" "ml_config" {
  workstation_config_id = local.workstation_config_name
  workstation_cluster_id = google_workstations_cluster.ml_workstations.workstation_cluster_id
  location              = var.region
  project               = var.project_id
  
  # VM configuration optimized for ML development
  host {
    gce_instance {
      machine_type                = var.workstation_machine_type
      boot_disk_size_gb          = var.workstation_disk_size
      disable_public_ip_addresses = true
      
      # Configure service account
      service_account = google_service_account.workstation_sa.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
      
      # Network tags for firewall rules
      tags = ["ml-workstation", "ssh-enabled"]
    }
  }
  
  # Persistent disk configuration
  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb      = var.workstation_disk_size
      fs_type      = "ext4"
      disk_type    = var.workstation_disk_type
      reclaim_policy = "DELETE"
    }
  }
  
  # Container configuration with ML tools
  container {
    image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
    
    # Environment variables for ML development
    env = {
      "GOOGLE_CLOUD_PROJECT" = var.project_id
      "GOOGLE_CLOUD_REGION"  = var.region
      "ML_ARTIFACTS_BUCKET"  = google_storage_bucket.ml_artifacts.name
      "VERTEX_AI_REGION"     = var.vertex_ai_region
    }
    
    # Run as non-root user for security
    run_as_user = 1000
  }
  
  # Encryption configuration
  encryption_key {
    kms_key = var.environment == "prod" ? google_kms_crypto_key.workstation_key[0].id : null
  }
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Workstations instance
resource "google_workstations_workstation" "ml_dev_workstation" {
  workstation_id         = "ml-dev-workstation"
  workstation_config_id  = google_workstations_workstation_config.ml_config.workstation_config_id
  workstation_cluster_id = google_workstations_cluster.ml_workstations.workstation_cluster_id
  location              = var.region
  project               = var.project_id
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# TPU v5e instance for large model training (conditional)
resource "google_tpu_v2_vm" "ml_tpu_training" {
  count = var.enable_tpu_training ? 1 : 0
  
  name               = "ml-tpu-training-${local.resource_suffix}"
  zone               = var.zone
  project            = var.project_id
  accelerator_type   = var.tpu_accelerator_type
  runtime_version    = "tpu-ubuntu2204-base"
  
  network_config {
    network    = google_compute_network.ml_network.id
    subnetwork = google_compute_subnetwork.ml_subnet.id
  }
  
  # Service account for TPU
  service_account {
    email = google_service_account.training_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # Apply common labels
  labels = local.common_labels
  
  # Network tags for firewall rules
  tags = ["ml-training", "tpu-enabled"]
  
  depends_on = [google_project_service.required_apis]
}

# GPU instance for mixed workloads (conditional)
resource "google_compute_instance" "ml_gpu_training" {
  count = var.enable_gpu_training ? 1 : 0
  
  name         = "ml-gpu-training-${local.resource_suffix}"
  machine_type = var.gpu_machine_type
  zone         = var.zone
  project      = var.project_id
  
  # Configure GPU accelerators
  guest_accelerator {
    type  = var.gpu_accelerator_type
    count = var.gpu_accelerator_count
  }
  
  # Use GPU-optimized OS image
  boot_disk {
    initialize_params {
      image = "projects/deeplearning-platform-release/global/images/family/pytorch-latest-gpu-debian-11"
      size  = 200
      type  = "pd-ssd"
    }
  }
  
  # Network configuration
  network_interface {
    network    = google_compute_network.ml_network.id
    subnetwork = google_compute_subnetwork.ml_subnet.id
    
    # No external IP for security
    access_config {
      # Ephemeral public IP
    }
  }
  
  # Service account configuration
  service_account {
    email = google_service_account.training_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # GPU-specific configuration
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = false
    provisioning_model  = "STANDARD"
  }
  
  # Network tags for firewall rules
  tags = ["ml-training", "gpu-enabled", "ssh-enabled"]
  
  # Apply common labels
  labels = local.common_labels
  
  # Startup script for GPU setup
  metadata_startup_script = file("${path.module}/scripts/gpu_setup.sh")
  
  depends_on = [google_project_service.required_apis]
}

# Vertex AI Metadata Store
resource "google_vertex_ai_metadata_store" "ml_metadata_store" {
  name     = "ml-metadata-store-${local.resource_suffix}"
  region   = var.vertex_ai_region
  project  = var.project_id
  
  description = "Metadata store for ML model lifecycle management"
  
  depends_on = [google_project_service.required_apis]
}

# Vertex AI Tensorboard instance
resource "google_vertex_ai_tensorboard" "ml_tensorboard" {
  display_name = "ML Tensorboard ${local.resource_suffix}"
  region       = var.vertex_ai_region
  project      = var.project_id
  
  description = "Tensorboard for ML experiment visualization"
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# KMS key for encryption (conditional for production)
resource "google_kms_key_ring" "ml_keyring" {
  count = var.environment == "prod" ? 1 : 0
  
  name     = "ml-keyring-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

resource "google_kms_crypto_key" "workstation_key" {
  count = var.environment == "prod" ? 1 : 0
  
  name     = "workstation-key-${local.resource_suffix}"
  key_ring = google_kms_key_ring.ml_keyring[0].id
  purpose  = "ENCRYPT_DECRYPT"
  
  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Binary Authorization policy for container security (conditional)
resource "google_binary_authorization_policy" "ml_policy" {
  count = var.enable_binary_authorization ? 1 : 0
  
  project = var.project_id
  
  # Default admission rule
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.ml_attestor[0].name
    ]
  }
  
  # Cluster-specific admission rules
  cluster_admission_rules {
    cluster                = "projects/${var.project_id}/zones/${var.zone}/clusters/*"
    evaluation_mode        = "REQUIRE_ATTESTATION"
    enforcement_mode       = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [
      google_binary_authorization_attestor.ml_attestor[0].name
    ]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Binary Authorization attestor (conditional)
resource "google_binary_authorization_attestor" "ml_attestor" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name    = "ml-attestor-${local.resource_suffix}"
  project = var.project_id
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.ml_note[0].name
  }
  
  depends_on = [google_project_service.required_apis]
}

# Container Analysis note for Binary Authorization (conditional)
resource "google_container_analysis_note" "ml_note" {
  count = var.enable_binary_authorization ? 1 : 0
  
  name    = "ml-attestor-note-${local.resource_suffix}"
  project = var.project_id
  
  attestation_authority {
    hint {
      human_readable_name = "ML Container Attestor"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Logging sink for ML operations (conditional)
resource "google_logging_project_sink" "ml_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "ml-logs-sink-${local.resource_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.ml_logs[0].name}"
  
  # Filter for ML-related logs
  filter = <<EOF
resource.type="gce_instance" AND
(resource.labels.instance_name=~"ml-.*" OR
 resource.labels.instance_name=~".*-training.*" OR
 resource.labels.instance_name=~".*-workstation.*")
EOF
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for logs (conditional)
resource "google_storage_bucket" "ml_logs" {
  count = var.enable_logging ? 1 : 0
  
  name          = "${local.bucket_name}-logs"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"
  
  # Lifecycle management for log retention
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Apply common labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for log sink to write to bucket
resource "google_storage_bucket_iam_member" "ml_logs_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.ml_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.ml_logs[0].writer_identity
}

# Cloud Monitoring notification channel (conditional)
resource "google_monitoring_notification_channel" "ml_alerts" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "ML Infrastructure Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = "ml-team@example.com"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Budget for cost management (conditional)
resource "google_billing_budget" "ml_budget" {
  count = var.enable_budget_alerts ? 1 : 0
  
  billing_account = data.google_billing_account.account[0].id
  display_name    = "ML Infrastructure Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    services = [
      "services/6F81-5844-456A",  # Compute Engine
      "services/95FF-2EF5-5EA1",  # Cloud TPU
      "services/9662-B51E-5089",  # Vertex AI
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis       = "CURRENT_SPEND"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Data source for billing account
data "google_billing_account" "account" {
  count = var.enable_budget_alerts ? 1 : 0
  open  = true
}

