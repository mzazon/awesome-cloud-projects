# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Construct resource names with suffix
  artifact_registry_repository_name = "${var.artifact_registry_repository_name}-${local.resource_suffix}"
  gke_cluster_name                 = "${var.gke_cluster_name}-${local.resource_suffix}"
  security_service_account_name    = "${var.security_service_account_name}-${local.resource_suffix}"
  attestor_name                    = "${var.attestor_name}-${local.resource_suffix}"
  kms_keyring_name                 = "${var.kms_keyring_name}-${local.resource_suffix}"
  vpc_network_name                 = "security-vpc-${local.resource_suffix}"
  
  # Labels to apply to all resources
  common_labels = merge(var.labels, {
    resource-suffix = local.resource_suffix
    recipe         = "container-security-scanning"
  })
}

# Data source to get current project information
data "google_project" "current" {}

# Data source to get current client configuration
data "google_client_config" "current" {}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# VPC Network for secure networking
resource "google_compute_network" "vpc_network" {
  name                    = local.vpc_network_name
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Subnet for GKE cluster
resource "google_compute_subnetwork" "vpc_subnet" {
  name          = "${local.vpc_network_name}-subnet"
  ip_cidr_range = "10.1.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods-range"
    ip_cidr_range = "10.2.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.6.0.0/16"
  }

  # Enable private Google access for nodes without external IPs
  private_ip_google_access = true
}

# Firewall rule for GKE master to nodes communication
resource "google_compute_firewall" "gke_master_to_nodes" {
  name    = "${local.vpc_network_name}-gke-master-to-nodes"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = ["gke-${local.gke_cluster_name}"]

  description = "Allow GKE master to communicate with nodes"
}

# Artifact Registry repository with vulnerability scanning
resource "google_artifact_registry_repository" "secure_repo" {
  provider = google-beta

  location      = var.region
  repository_id = local.artifact_registry_repository_name
  description   = "Secure container repository with vulnerability scanning for recipe demonstration"
  format        = "DOCKER"

  # Enable vulnerability scanning
  docker_config {
    immutable_tags = false
  }

  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Service account for security automation
resource "google_service_account" "security_scanner" {
  account_id   = local.security_service_account_name
  display_name = "Security Scanner Service Account"
  description  = "Service account for automated security scanning and attestation processes"

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for security service account
resource "google_project_iam_member" "security_scanner_bindings" {
  for_each = toset([
    "roles/binaryauthorization.attestorsAdmin",
    "roles/containeranalysis.notes.editor",
    "roles/containeranalysis.notes.occurrences.viewer",
    "roles/cloudkms.cryptoKeyVersions.useToSign",
    "roles/cloudkms.signerVerifier"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.security_scanner.email}"
}

# Grant Cloud Build service account permissions to use security service account
resource "google_service_account_iam_member" "cloud_build_security_sa_user" {
  service_account_id = google_service_account.security_scanner.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Build service account additional permissions
resource "google_project_iam_member" "cloud_build_additional_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/containeranalysis.admin",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# KMS Key Ring for cryptographic operations
resource "google_kms_key_ring" "security_keyring" {
  name     = local.kms_keyring_name
  location = var.region

  depends_on = [google_project_service.required_apis]
}

# KMS Crypto Key for signing attestations
resource "google_kms_crypto_key" "security_signing_key" {
  name     = var.kms_key_name
  key_ring = google_kms_key_ring.security_keyring.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm = "RSA_SIGN_PKCS1_4096_SHA512"
  }

  # Key rotation policy (optional, for long-term use)
  rotation_period = "7776000s" # 90 days

  labels = local.common_labels

  lifecycle {
    prevent_destroy = true
  }
}

# Container Analysis note for attestation
resource "google_container_analysis_note" "attestor_note" {
  name = var.attestor_note_name

  attestation_authority {
    hint {
      human_readable_name = "Security vulnerability scan attestor for container images"
    }
  }

  description = "Note for security attestations created by vulnerability scanning pipeline"

  depends_on = [google_project_service.required_apis]
}

# Binary Authorization attestor
resource "google_binary_authorization_attestor" "security_attestor" {
  name = local.attestor_name
  description = "Attestor for verifying container image security compliance"

  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
    public_keys {
      id = google_kms_crypto_key.security_signing_key.id
      ascii_armored_pgp_public_key = ""
      pkix_public_key {
        public_key_pem      = ""
        signature_algorithm = "RSA_PSS_4096_SHA512"
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Add KMS public key to attestor
resource "google_binary_authorization_attestor_iam_member" "attestor_admin" {
  project  = var.project_id
  attestor = google_binary_authorization_attestor.security_attestor.name
  role     = "roles/binaryauthorization.attestorsAdmin"
  member   = "serviceAccount:${google_service_account.security_scanner.email}"
}

# GKE cluster with Binary Authorization enabled
resource "google_container_cluster" "security_cluster" {
  provider = google-beta

  name     = local.gke_cluster_name
  location = var.zone
  
  # Network configuration
  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.vpc_subnet.name

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Enable Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Security and compliance features
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  # Workload Identity configuration
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled  = true
      provider = "CALICO"
    }
  }

  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-range"
    services_secondary_range_name = "services-range"
  }

  # Master authorized networks (if using private cluster)
  dynamic "master_authorized_networks_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      cidr_blocks {
        cidr_block   = "0.0.0.0/0"
        display_name = "All networks (adjust for production use)"
      }
    }
  }

  # Logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Release channel for automatic updates
  release_channel {
    channel = "STABLE"
  }

  # Security and maintenance configuration
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T02:00:00Z"
      end_time   = "2023-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  # Node configuration defaults
  node_config {
    machine_type = var.gke_machine_type
    
    # Security features
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Service account for nodes
    service_account = google_service_account.security_scanner.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  # Resource labels
  resource_labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.vpc_subnet
  ]
}

# Separate node pool for better management
resource "google_container_node_pool" "security_cluster_nodes" {
  provider = google-beta

  name       = "${local.gke_cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.security_cluster.name
  node_count = var.gke_node_count

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }

  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_disk_size_gb
    disk_type    = "pd-standard"

    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity
    dynamic "workload_metadata_config" {
      for_each = var.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }

    # Service account for nodes
    service_account = google_service_account.security_scanner.email
    
    # OAuth scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Node labels and tags
    labels = merge(local.common_labels, {
      node-pool = "security-cluster-pool"
    })
    
    tags = ["gke-${local.gke_cluster_name}"]

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  depends_on = [google_container_cluster.security_cluster]
}

# Binary Authorization policy
resource "google_binary_authorization_policy" "security_policy" {
  # Default admission rule requiring attestations
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    
    require_attestations_by = [
      google_binary_authorization_attestor.security_attestor.name
    ]
  }

  # Global policy evaluation mode
  global_policy_evaluation_mode = "ENABLE"

  # Admission whitelist for system images
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "k8s.gcr.io/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }

  # Cluster-specific admission rules
  cluster_admission_rules {
    cluster                = "${var.zone}.${google_container_cluster.security_cluster.name}"
    evaluation_mode        = "REQUIRE_ATTESTATION"
    enforcement_mode       = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [
      google_binary_authorization_attestor.security_attestor.name
    ]
  }

  depends_on = [
    google_project_service.required_apis,
    google_binary_authorization_attestor.security_attestor
  ]
}

# Security Command Center notification configuration (if enabled)
resource "google_security_center_notification_config" "vulnerability_notifications" {
  count = var.enable_security_command_center ? 1 : 0

  config_id    = "vulnerability-notifications-${local.resource_suffix}"
  organization = data.google_project.current.number
  description  = "Notification config for container vulnerability findings"

  pubsub_topic = google_pubsub_topic.security_notifications[0].id

  streaming_config {
    filter = "category=\"VULNERABILITY\""
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for security notifications (if Security Command Center is enabled)
resource "google_pubsub_topic" "security_notifications" {
  count = var.enable_security_command_center ? 1 : 0

  name = "security-notifications-${local.resource_suffix}"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM permissions for Artifact Registry vulnerability scanning
resource "google_project_iam_member" "artifact_registry_scanner" {
  project = var.project_id
  role    = "roles/containeranalysis.admin"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}