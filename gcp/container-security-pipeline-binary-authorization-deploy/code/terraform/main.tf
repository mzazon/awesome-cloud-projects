# Container Security Pipeline with Binary Authorization and Cloud Deploy
# This Terraform configuration deploys a complete container security pipeline on Google Cloud Platform
# featuring Binary Authorization for policy enforcement, Cloud Deploy for progressive deployments,
# and comprehensive security controls for production workloads.

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate consistent resource suffix
  resource_suffix = var.resource_suffix != null ? var.resource_suffix : random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment_date = formatdate("YYYY-MM-DD", timestamp())
    resource_suffix = local.resource_suffix
  })
  
  # Cluster names with suffix
  staging_cluster_name    = "${var.gke_cluster_config.staging_cluster_name}-${local.resource_suffix}"
  production_cluster_name = "${var.gke_cluster_config.production_cluster_name}-${local.resource_suffix}"
  
  # Binary Authorization resource names
  attestor_name = "${var.binary_authorization_config.attestor_name}-${local.resource_suffix}"
  note_name     = "${var.binary_authorization_config.note_name}-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  count = var.enable_apis ? length(local.required_apis) : 0
  
  project = var.project_id
  service = local.required_apis[count.index]
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

locals {
  required_apis = [
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "binaryauthorization.googleapis.com",
    "clouddeploy.googleapis.com",
    "containeranalysis.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Wait for APIs to be enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create VPC network for secure communication
resource "google_compute_network" "container_security_network" {
  name                    = "${var.network_config.network_name}-${local.resource_suffix}"
  auto_create_subnetworks = false
  description             = "VPC network for container security pipeline"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create subnet for GKE clusters
resource "google_compute_subnetwork" "container_security_subnet" {
  name          = "${var.network_config.subnet_name}-${local.resource_suffix}"
  ip_cidr_range = var.network_config.subnet_cidr
  region        = var.region
  network       = google_compute_network.container_security_network.id
  description   = "Subnet for GKE clusters with container security"
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = var.network_config.enable_private_google_access
  
  # Enable flow logs for network monitoring
  dynamic "log_config" {
    for_each = var.network_config.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
  
  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.2.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.3.0.0/16"
  }
}

# Create firewall rules for GKE clusters
resource "google_compute_firewall" "container_security_firewall" {
  name    = "container-security-firewall-${local.resource_suffix}"
  network = google_compute_network.container_security_network.name
  
  description = "Firewall rules for container security pipeline"
  
  # Allow internal communication within the network
  allow {
    protocol = "tcp"
    ports    = ["443", "80", "8080", "10250"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  source_ranges = [var.network_config.subnet_cidr]
  target_tags   = ["container-security"]
}

# Create Artifact Registry repository for secure container images
resource "google_artifact_registry_repository" "secure_apps_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repository_id
  description   = var.artifact_registry_description
  format        = "DOCKER"
  
  labels = local.common_labels
  
  # Enable vulnerability scanning
  dynamic "vulnerability_scanning_config" {
    for_each = var.enable_vulnerability_scanning ? [1] : []
    content {
      enablement_config = "INHERITED"
    }
  }
  
  # Docker-specific configuration
  docker_config {
    immutable_tags = true
  }
  
  # Cleanup policies for cost optimization
  cleanup_policies {
    id     = "delete-untagged-images"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }
  
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create service accounts for different components
resource "google_service_account" "cloud_build_sa" {
  account_id   = "${var.service_account_config.cloud_build_sa_id}-${local.resource_suffix}"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build operations with Binary Authorization"
  
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_service_account" "cloud_deploy_sa" {
  account_id   = "${var.service_account_config.cloud_deploy_sa_id}-${local.resource_suffix}"
  display_name = "Cloud Deploy Service Account"
  description  = "Service account for Cloud Deploy operations"
  
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_service_account" "gke_workload_sa" {
  account_id   = "${var.service_account_config.gke_workload_sa_id}-${local.resource_suffix}"
  display_name = "GKE Workload Service Account"
  description  = "Service account for GKE workloads with Workload Identity"
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloud_build_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/containeranalysis.notes.editor",
    "roles/binaryauthorization.attestorsVerifier",
    "roles/storage.admin",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# IAM bindings for Cloud Deploy service account
resource "google_project_iam_member" "cloud_deploy_sa_roles" {
  for_each = toset([
    "roles/clouddeploy.operator",
    "roles/container.clusterViewer",
    "roles/container.developer",
    "roles/artifactregistry.reader",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_deploy_sa.email}"
}

# Create Container Analysis note for Binary Authorization
resource "google_container_analysis_note" "attestor_note" {
  name = local.note_name
  
  attestation_authority {
    hint {
      human_readable_name = "Build Verification Attestor"
    }
  }
  
  short_description = "Container build verification attestor"
  long_description  = "This note is used for Binary Authorization attestations to verify container builds"
  
  related_url {
    url   = "https://cloud.google.com/binary-authorization/docs"
    label = "Binary Authorization Documentation"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Binary Authorization attestor
resource "google_binary_authorization_attestor" "build_attestor" {
  name = local.attestor_name
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
    
    # Use a placeholder PGP key - in production, use KMS keys
    public_keys {
      ascii_armored_pgp_public_key = <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----
Comment: User-ID: Build Attestor <build@example.com>

mQENBGJABCEBCADKnwVWQV8KN5cOYprZPZLLdJjcbhyOLJ/oJJzVNmNGBmQhGk2d
kLKpgHZ3jIbKRXrFHkiJnzVlRjAc8QCyUJg+cqsRdFf3+lkF9g7JjYuBtGm0K6yJ
wYjxjpNfIHnmGYYWCsJSN8lLbJzYcZMzMBxCzUfHRYHdnRYRlQgQXeThL4WKhH9G
aJhcjAQNZNGcMzIzMjIzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMz
MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMz
MzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMz
ABEBAAG0G0J1aWxkIEF0dGVzdG9yIDxidWlsZEBleGFtcGxlLmNvbT6JATgEEwEI
ACIFAmJABCECGwMGCwkIBwMCBhUIAgkKCwQWAgMBAh4BAheAAAoJENG2h1L8fZDt
+WgIAKoEhgJKwHNGLJtVmvxEJhGsGm5lbpQhGFBIBhPSMCGJJqLjkQqcHEjc8UDJ
5dNrjkKZzJjLwEJOYkNgJk8qFTjBaLJJ5qC3B3B6HJYyHr7FXFnKPdGdYUQEGQMJ
dGjcb6AjqFYCMEZHQWlNnmv2VYjGJdNzRJSCJgPHQJDIEzUL8QhCpPfBMRdQNYXI
YFhUfIWUNEwmRmJ9BZFbHQEWHHdqy6rZWZNGCpTQSFNjYJEBAAEBAAEBAAEBAAEB
AAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAE
BAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAEBAAE=
=example
-----END PGP PUBLIC KEY BLOCK-----
EOF
    }
  }
  
  depends_on = [google_container_analysis_note.attestor_note]
}

# Create Binary Authorization policy
resource "google_binary_authorization_policy" "container_security_policy" {
  # Global policy evaluation mode
  global_policy_evaluation_mode = var.binary_authorization_config.global_policy_evaluation_mode
  
  # Default admission rule requiring attestations
  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binary_authorization_config.default_enforcement_mode
    require_attestations_by = [google_binary_authorization_attestor.build_attestor.name]
  }
  
  # Cluster-specific rule for staging (more permissive)
  cluster_admission_rules {
    cluster                 = "${var.zone}.${local.staging_cluster_name}"
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binary_authorization_config.staging_enforcement_mode
    require_attestations_by = []
  }
  
  # Cluster-specific rule for production (strict enforcement)
  cluster_admission_rules {
    cluster                 = "${var.zone}.${local.production_cluster_name}"
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binary_authorization_config.production_enforcement_mode
    require_attestations_by = [google_binary_authorization_attestor.build_attestor.name]
  }
  
  # Whitelist patterns for trusted base images
  admission_whitelist_patterns {
    name_pattern = "gcr.io/distroless/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  
  depends_on = [google_binary_authorization_attestor.build_attestor]
}

# Create staging GKE cluster
resource "google_container_cluster" "staging_cluster" {
  name        = local.staging_cluster_name
  location    = var.zone
  description = "Staging GKE cluster for container security pipeline"
  
  # Network configuration
  network    = google_compute_network.container_security_network.id
  subnetwork = google_compute_subnetwork.container_security_subnet.id
  
  # Remove default node pool (we'll create a custom one)
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Binary Authorization configuration
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  
  # Workload Identity configuration
  dynamic "workload_identity_config" {
    for_each = var.security_config.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.gke_cluster_config.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.gke_cluster_config.enable_private_nodes ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = var.gke_cluster_config.enable_private_endpoint
      master_ipv4_cidr_block  = var.gke_cluster_config.master_ipv4_cidr_block
    }
  }
  
  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }
  
  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.security_config.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.security_config.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }
  
  # Logging and monitoring configuration
  dynamic "logging_config" {
    for_each = var.monitoring_config.enable_logging ? [1] : []
    content {
      enable_components = [
        "SYSTEM_COMPONENTS",
        "WORKLOADS",
        "API_SERVER"
      ]
    }
  }
  
  dynamic "monitoring_config" {
    for_each = var.monitoring_config.enable_monitoring ? [1] : []
    content {
      enable_components = [
        "SYSTEM_COMPONENTS",
        "WORKLOADS"
      ]
    }
  }
  
  # Security posture configuration
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  
  resource_labels = local.common_labels
  
  depends_on = [
    google_compute_subnetwork.container_security_subnet,
    google_binary_authorization_policy.container_security_policy,
    time_sleep.wait_for_apis
  ]
}

# Create production GKE cluster
resource "google_container_cluster" "production_cluster" {
  name        = local.production_cluster_name
  location    = var.zone
  description = "Production GKE cluster for container security pipeline"
  
  # Network configuration
  network    = google_compute_network.container_security_network.id
  subnetwork = google_compute_subnetwork.container_security_subnet.id
  
  # Remove default node pool (we'll create a custom one)
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Binary Authorization configuration
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  
  # Workload Identity configuration
  dynamic "workload_identity_config" {
    for_each = var.security_config.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }
  
  # Network policy configuration
  dynamic "network_policy" {
    for_each = var.gke_cluster_config.enable_network_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.gke_cluster_config.enable_private_nodes ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = var.gke_cluster_config.enable_private_endpoint
      master_ipv4_cidr_block  = var.gke_cluster_config.master_ipv4_cidr_block
    }
  }
  
  # IP allocation policy for secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }
  
  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.security_config.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.security_config.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }
  
  # Logging and monitoring configuration
  dynamic "logging_config" {
    for_each = var.monitoring_config.enable_logging ? [1] : []
    content {
      enable_components = [
        "SYSTEM_COMPONENTS",
        "WORKLOADS",
        "API_SERVER"
      ]
    }
  }
  
  dynamic "monitoring_config" {
    for_each = var.monitoring_config.enable_monitoring ? [1] : []
    content {
      enable_components = [
        "SYSTEM_COMPONENTS",
        "WORKLOADS"
      ]
    }
  }
  
  # Security posture configuration
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  
  resource_labels = local.common_labels
  
  depends_on = [
    google_compute_subnetwork.container_security_subnet,
    google_binary_authorization_policy.container_security_policy,
    time_sleep.wait_for_apis
  ]
}

# Create node pool for staging cluster
resource "google_container_node_pool" "staging_node_pool" {
  name     = "${local.staging_cluster_name}-node-pool"
  location = var.zone
  cluster  = google_container_cluster.staging_cluster.name
  
  node_count = var.gke_cluster_config.node_count
  
  # Node configuration
  node_config {
    machine_type = var.gke_cluster_config.machine_type
    disk_size_gb = var.gke_cluster_config.disk_size_gb
    disk_type    = var.gke_cluster_config.disk_type
    image_type   = "COS_CONTAINERD"
    
    # Service account for node pool
    service_account = google_service_account.gke_workload_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Workload Identity configuration
    dynamic "workload_metadata_config" {
      for_each = var.security_config.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
    
    # Shielded instance configuration
    dynamic "shielded_instance_config" {
      for_each = var.security_config.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = var.security_config.enable_secure_boot
        enable_integrity_monitoring = var.security_config.enable_integrity_monitoring
      }
    }
    
    # Network tags for firewall rules
    tags = ["container-security", "staging"]
    
    labels = merge(local.common_labels, {
      environment = "staging"
    })
  }
  
  # Node pool management
  management {
    auto_repair  = var.gke_cluster_config.enable_autorepair
    auto_upgrade = var.gke_cluster_config.enable_autoupgrade
  }
  
  depends_on = [google_container_cluster.staging_cluster]
}

# Create node pool for production cluster
resource "google_container_node_pool" "production_node_pool" {
  name     = "${local.production_cluster_name}-node-pool"
  location = var.zone
  cluster  = google_container_cluster.production_cluster.name
  
  node_count = var.gke_cluster_config.node_count
  
  # Node configuration
  node_config {
    machine_type = var.gke_cluster_config.machine_type
    disk_size_gb = var.gke_cluster_config.disk_size_gb
    disk_type    = var.gke_cluster_config.disk_type
    image_type   = "COS_CONTAINERD"
    
    # Service account for node pool
    service_account = google_service_account.gke_workload_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Workload Identity configuration
    dynamic "workload_metadata_config" {
      for_each = var.security_config.enable_workload_identity ? [1] : []
      content {
        mode = "GKE_METADATA"
      }
    }
    
    # Shielded instance configuration
    dynamic "shielded_instance_config" {
      for_each = var.security_config.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = var.security_config.enable_secure_boot
        enable_integrity_monitoring = var.security_config.enable_integrity_monitoring
      }
    }
    
    # Network tags for firewall rules
    tags = ["container-security", "production"]
    
    labels = merge(local.common_labels, {
      environment = "production"
    })
  }
  
  # Node pool management
  management {
    auto_repair  = var.gke_cluster_config.enable_autorepair
    auto_upgrade = var.gke_cluster_config.enable_autoupgrade
  }
  
  depends_on = [google_container_cluster.production_cluster]
}

# Create Cloud Deploy staging target
resource "google_clouddeploy_target" "staging_target" {
  location = var.region
  name     = var.cloud_deploy_config.staging_target_name
  
  description = "Staging target for container security pipeline"
  
  # GKE cluster target configuration
  gke {
    cluster     = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.staging_cluster.name}"
    internal_ip = var.gke_cluster_config.enable_private_nodes
  }
  
  # Execution configurations
  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    execution_timeout = var.cloud_deploy_config.deployment_timeout
    service_account   = google_service_account.cloud_deploy_sa.email
    
    # Use the default worker pool for staging
    worker_pool = ""
  }
  
  require_approval = false # Staging doesn't require approval
  
  annotations = {
    environment = "staging"
    cluster     = google_container_cluster.staging_cluster.name
  }
  
  labels = merge(local.common_labels, {
    environment = "staging"
  })
  
  depends_on = [
    google_container_cluster.staging_cluster,
    google_container_node_pool.staging_node_pool
  ]
}

# Create Cloud Deploy production target
resource "google_clouddeploy_target" "production_target" {
  location = var.region
  name     = var.cloud_deploy_config.production_target_name
  
  description = "Production target for container security pipeline with canary deployment"
  
  # GKE cluster target configuration
  gke {
    cluster     = "projects/${var.project_id}/locations/${var.zone}/clusters/${google_container_cluster.production_cluster.name}"
    internal_ip = var.gke_cluster_config.enable_private_nodes
  }
  
  # Execution configurations
  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    execution_timeout = var.cloud_deploy_config.deployment_timeout
    service_account   = google_service_account.cloud_deploy_sa.email
    
    # Use the default worker pool for production
    worker_pool = ""
  }
  
  require_approval = var.cloud_deploy_config.require_approval
  
  annotations = {
    environment = "production"
    cluster     = google_container_cluster.production_cluster.name
  }
  
  labels = merge(local.common_labels, {
    environment = "production"
  })
  
  depends_on = [
    google_container_cluster.production_cluster,
    google_container_node_pool.production_node_pool
  ]
}

# Create Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "secure_app_pipeline" {
  location = var.region
  name     = var.cloud_deploy_config.pipeline_name
  
  description = "Secure container deployment pipeline with Binary Authorization and canary deployment"
  
  # Serial pipeline configuration
  serial_pipeline {
    # Staging stage
    stages {
      target_id = google_clouddeploy_target.staging_target.name
      profiles  = []
      
      # Standard deployment strategy for staging
      strategy {
        standard {
          verify = false # Skip verification in staging for faster feedback
        }
      }
    }
    
    # Production stage with canary deployment
    stages {
      target_id = google_clouddeploy_target.production_target.name
      profiles  = []
      
      # Canary deployment strategy
      strategy {
        canary {
          runtime_config {
            kubernetes {
              service_networking {
                service    = "secure-app-service"
                deployment = "secure-app"
              }
            }
          }
          
          canary_deployment {
            percentages = var.cloud_deploy_config.canary_percentages
            verify      = var.cloud_deploy_config.enable_canary_verification
          }
        }
      }
    }
  }
  
  # Suspend pipeline if needed
  suspended = false
  
  annotations = {
    pipeline_type = "container-security"
    binary_auth   = "enabled"
    canary_deploy = "enabled"
  }
  
  labels = merge(local.common_labels, {
    pipeline_type = "container-security"
  })
  
  depends_on = [
    google_clouddeploy_target.staging_target,
    google_clouddeploy_target.production_target
  ]
}

# Create IAM policy binding for Artifact Registry
resource "google_artifact_registry_repository_iam_member" "repo_readers" {
  for_each = toset([
    "serviceAccount:${google_service_account.cloud_build_sa.email}",
    "serviceAccount:${google_service_account.cloud_deploy_sa.email}",
    "serviceAccount:${google_service_account.gke_workload_sa.email}"
  ])
  
  project    = var.project_id
  location   = google_artifact_registry_repository.secure_apps_repo.location
  repository = google_artifact_registry_repository.secure_apps_repo.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}

# Create IAM policy binding for Binary Authorization attestor
resource "google_binary_authorization_attestor_iam_member" "attestor_users" {
  attestor = google_binary_authorization_attestor.build_attestor.name
  role     = "roles/binaryauthorization.attestorsVerifier"
  member   = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# Create IAM policy binding for Container Analysis note
resource "google_container_analysis_note_iam_member" "note_users" {
  note   = google_container_analysis_note.attestor_note.name
  role   = "roles/containeranalysis.notes.occurrences.viewer"
  member = "serviceAccount:${google_service_account.cloud_build_sa.email}"
}

# Create Workload Identity binding for GKE service account
resource "google_service_account_iam_member" "workload_identity_binding" {
  count = var.security_config.enable_workload_identity ? 1 : 0
  
  service_account_id = google_service_account.gke_workload_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/secure-app-ksa]"
}