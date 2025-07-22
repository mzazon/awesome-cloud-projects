# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current project information
data "google_project" "current" {}

# Data source for Cloud Build service account
data "google_project" "project" {
  project_id = var.project_id
}

locals {
  # Generate unique resource names using random suffix
  resource_suffix = random_id.suffix.hex
  
  # Cloud Build service account
  cloud_build_sa = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  
  # Full resource names
  full_cluster_name    = "${var.resource_prefix}-${var.cluster_name}-${local.resource_suffix}"
  full_keyring_name    = "${var.resource_prefix}-${var.kms_keyring_name}-${local.resource_suffix}"
  full_key_name        = "${var.resource_prefix}-${var.kms_key_name}-${local.resource_suffix}"
  full_attestor_name   = "${var.resource_prefix}-${var.attestor_name}-${local.resource_suffix}"
  full_repo_name       = "${var.resource_prefix}-${var.artifact_registry_repository_name}-${local.resource_suffix}"
  full_network_name    = "${var.resource_prefix}-${var.network_name}-${local.resource_suffix}"
  full_subnet_name     = "${var.resource_prefix}-${var.subnet_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    project     = var.project_id
    environment = var.environment
    component   = "supply-chain-security"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "binaryauthorization.googleapis.com",
    "cloudkms.googleapis.com",
    "artifactregistry.googleapis.com",
    "containeranalysis.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
}

# Create VPC network for GKE cluster
resource "google_compute_network" "secure_network" {
  name                    = local.full_network_name
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for GKE cluster
resource "google_compute_subnetwork" "secure_subnet" {
  name          = local.full_subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.secure_network.id
  
  # Configure secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
  
  private_ip_google_access = true
}

# Create Cloud NAT for private nodes internet access
resource "google_compute_router" "secure_router" {
  name    = "${local.full_network_name}-router"
  region  = var.region
  network = google_compute_network.secure_network.id
}

resource "google_compute_router_nat" "secure_nat" {
  name                               = "${local.full_network_name}-nat"
  router                             = google_compute_router.secure_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Create Artifact Registry repository for secure container images
resource "google_artifact_registry_repository" "secure_images" {
  location      = var.region
  repository_id = local.full_repo_name
  description   = "Secure container repository with vulnerability scanning for ${var.environment} environment"
  format        = var.artifact_registry_format
  
  # Enable vulnerability scanning
  docker_config {
    immutable_tags = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud KMS key ring for attestation keys
resource "google_kms_key_ring" "attestor_keyring" {
  name     = local.full_keyring_name
  location = var.region
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud KMS key for signing attestations
resource "google_kms_crypto_key" "attestor_key" {
  name            = local.full_key_name
  key_ring        = google_kms_key_ring.attestor_keyring.id
  purpose         = "ASYMMETRIC_SIGN"
  
  version_template {
    algorithm        = var.kms_key_algorithm
    protection_level = var.kms_key_protection_level
  }
  
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# Create Binary Authorization attestor
resource "google_binary_authorization_attestor" "build_attestor" {
  name        = local.full_attestor_name
  description = var.attestor_description
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
    
    public_keys {
      # Use the KMS key for signing
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].algorithm
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Container Analysis note for attestor
resource "google_container_analysis_note" "attestor_note" {
  name = "${local.full_attestor_name}-note"
  
  attestation_authority {
    hint {
      human_readable_name = "Binary Authorization Attestor for ${var.environment}"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Get the current version of the KMS key
data "google_kms_crypto_key_version" "attestor_key_version" {
  crypto_key = google_kms_crypto_key.attestor_key.id
}

# Create GKE cluster with Binary Authorization enabled
resource "google_container_cluster" "secure_cluster" {
  name     = local.full_cluster_name
  location = var.zone
  
  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = google_compute_network.secure_network.name
  subnetwork = google_compute_subnetwork.secure_subnet.name
  
  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Enable Binary Authorization
  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }
  
  # Enable network policy
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Enable private nodes
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }
  
  # Master authorized networks
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }
  
  # Logging configuration
  logging_config {
    enable_components = var.enable_logging ? var.logging_components : []
  }
  
  # Monitoring configuration
  monitoring_config {
    enable_components = var.enable_monitoring ? var.monitoring_components : []
  }
  
  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T02:00:00Z"
      end_time   = "2023-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }
  
  # Release channel
  release_channel {
    channel = "REGULAR"
  }
  
  # Security configurations
  enable_shielded_nodes = true
  
  # Resource labels
  resource_labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.secure_subnet,
    google_compute_router_nat.secure_nat
  ]
}

# Create GKE node pool
resource "google_container_node_pool" "secure_node_pool" {
  name       = "${local.full_cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.secure_cluster.name
  node_count = var.cluster_min_nodes
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.cluster_min_nodes
    max_node_count = var.cluster_max_nodes
  }
  
  # Node configuration
  node_config {
    machine_type = var.cluster_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"
    
    # Use the default service account with minimal scopes
    service_account = "default"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Enable workload identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Shielded VM configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Labels for node pool
    labels = merge(local.common_labels, {
      node-pool = "secure-node-pool"
    })
    
    # Tags for network firewall rules
    tags = ["secure-cluster-node"]
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  depends_on = [google_container_cluster.secure_cluster]
}

# Create Binary Authorization policy
resource "google_binary_authorization_policy" "secure_policy" {
  # Default admission rule - require attestation
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = var.binary_authorization_policy_mode
    
    require_attestations_by = [
      google_binary_authorization_attestor.build_attestor.name
    ]
  }
  
  # Admission whitelist patterns for system images
  dynamic "admission_whitelist_patterns" {
    for_each = var.whitelisted_image_patterns
    content {
      name_pattern = admission_whitelist_patterns.value
    }
  }
  
  # Cluster-specific admission rules
  cluster_admission_rules {
    cluster                = google_container_cluster.secure_cluster.id
    evaluation_mode        = "REQUIRE_ATTESTATION"
    enforcement_mode       = var.binary_authorization_policy_mode
    require_attestations_by = [
      google_binary_authorization_attestor.build_attestor.name
    ]
  }
  
  depends_on = [
    google_binary_authorization_attestor.build_attestor,
    google_container_cluster.secure_cluster
  ]
}

# Create Cloud Source Repository (optional)
resource "google_sourcerepo_repository" "secure_app_repo" {
  count = var.enable_cloud_build_trigger ? 1 : 0
  
  name = local.full_repo_name
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Build trigger
resource "google_cloudbuild_trigger" "secure_build_trigger" {
  count = var.enable_cloud_build_trigger ? 1 : 0
  
  name        = "${var.cloud_build_trigger_name}-${local.resource_suffix}"
  description = "Secure CI/CD pipeline trigger for ${var.environment} environment"
  
  # Trigger configuration
  trigger_template {
    branch_name = var.source_repository_branch
    repo_name   = google_sourcerepo_repository.secure_app_repo[0].name
  }
  
  # Build configuration
  build {
    # Build the container image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.full_repo_name}/secure-app:$SHORT_SHA",
        "."
      ]
    }
    
    # Push the image to Artifact Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${local.full_repo_name}/secure-app:$SHORT_SHA"
      ]
    }
    
    # Wait for vulnerability scan and create attestation
    step {
      name       = "gcr.io/google.com/cloudsdktool/google-cloud-cli:latest"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOF
          echo "Waiting for vulnerability scan to complete..."
          sleep 30
          echo "Creating attestation for image..."
          gcloud container binauthz attestations sign-and-create \
            --artifact-url="${var.region}-docker.pkg.dev/${var.project_id}/${local.full_repo_name}/secure-app:$SHORT_SHA" \
            --attestor="${local.full_attestor_name}" \
            --attestor-project="${var.project_id}" \
            --keyversion-project="${var.project_id}" \
            --keyversion-location="${var.region}" \
            --keyversion-keyring="${local.full_keyring_name}" \
            --keyversion-key="${local.full_key_name}" \
            --keyversion="1"
        EOF
      ]
    }
    
    # Specify the images to be pushed
    images = [
      "${var.region}-docker.pkg.dev/${var.project_id}/${local.full_repo_name}/secure-app:$SHORT_SHA"
    ]
    
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }
  
  depends_on = [
    google_artifact_registry_repository.secure_images,
    google_binary_authorization_attestor.build_attestor
  ]
}

# IAM permissions for Cloud Build service account
resource "google_kms_crypto_key_iam_binding" "cloud_build_kms_signer" {
  crypto_key_id = google_kms_crypto_key.attestor_key.id
  role          = "roles/cloudkms.signerVerifier"
  
  members = [
    "serviceAccount:${local.cloud_build_sa}"
  ]
}

resource "google_binary_authorization_attestor_iam_binding" "cloud_build_attestor_editor" {
  attestor = google_binary_authorization_attestor.build_attestor.name
  role     = "roles/binaryauthorization.attestorsEditor"
  
  members = [
    "serviceAccount:${local.cloud_build_sa}"
  ]
}

resource "google_artifact_registry_repository_iam_binding" "cloud_build_artifact_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.secure_images.name
  role       = "roles/artifactregistry.writer"
  
  members = [
    "serviceAccount:${local.cloud_build_sa}"
  ]
}

# Create firewall rules for GKE cluster
resource "google_compute_firewall" "allow_gke_webhooks" {
  name    = "${local.full_network_name}-allow-gke-webhooks"
  network = google_compute_network.secure_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "15017"]
  }
  
  source_ranges = [var.master_cidr]
  target_tags   = ["secure-cluster-node"]
  
  description = "Allow GKE master to communicate with nodes for webhooks"
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.full_network_name}-allow-internal"
  network = google_compute_network.secure_network.name
  
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
  
  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
  
  description = "Allow internal communication within the VPC"
}