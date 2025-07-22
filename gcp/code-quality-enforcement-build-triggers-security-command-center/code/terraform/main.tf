# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  service_account_name = "${var.resource_prefix}-build-sa-${local.resource_suffix}"
  attestor_name = "${var.resource_prefix}-attestor-${local.resource_suffix}"
  trigger_name = "${var.resource_prefix}-trigger-${local.resource_suffix}"
  repo_full_name = "${var.repository_name}-${local.resource_suffix}"
  
  # Merge default labels with user-provided labels
  default_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    suffix      = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "sourcerepo.googleapis.com", 
    "binaryauthorization.googleapis.com",
    "securitycenter.googleapis.com",
    "container.googleapis.com",
    "containeranalysis.googleapis.com",
    "run.googleapis.com",
    "cloudkms.googleapis.com",
    "containerregistry.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of essential services
  disable_dependent_services = false
  disable_on_destroy = false
}

# Create Cloud Source Repository for storing application code
resource "google_sourcerepo_repository" "app_repo" {
  name    = local.repo_full_name
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Build with security permissions
resource "google_service_account" "build_service_account" {
  account_id   = local.service_account_name
  display_name = "Build Security Service Account"
  description  = "Service account for automated security pipeline"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the Cloud Build service account
resource "google_project_iam_member" "build_service_account_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/binaryauthorization.attestorsEditor", 
    "roles/containeranalysis.notes.editor",
    "roles/securitycenter.findingsEditor",
    "roles/storage.admin",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/cloudkms.signerVerifier"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.build_service_account.email}"
}

# Create KMS key ring for Binary Authorization attestation signing
resource "google_kms_key_ring" "binauthz_keyring" {
  name     = var.kms_key_ring_name
  location = "global"
  project  = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create KMS key for attestation signing with asymmetric algorithm
resource "google_kms_crypto_key" "attestor_key" {
  name            = var.kms_key_name
  key_ring        = google_kms_key_ring.binauthz_keyring.id
  purpose         = "ASYMMETRIC_SIGN"
  
  version_template {
    algorithm = "RSA_SIGN_PKCS1_4096_SHA512"
  }
  
  labels = local.default_labels
  
  # Prevent accidental deletion of cryptographic keys
  lifecycle {
    prevent_destroy = true
  }
}

# Create Binary Authorization attestor for policy enforcement
resource "google_binary_authorization_attestor" "quality_attestor" {
  name    = local.attestor_name
  project = var.project_id
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
    public_keys {
      id = google_kms_crypto_key.attestor_key.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].algorithm
      }
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key.attestor_key
  ]
}

# Get the current version of the attestor key for public key extraction
data "google_kms_crypto_key_version" "attestor_key_version" {
  crypto_key = google_kms_crypto_key.attestor_key.id
  version    = "1"
}

# Create Container Analysis note for the attestor
resource "google_container_analysis_note" "attestor_note" {
  name    = local.attestor_name
  project = var.project_id
  
  attestation_authority {
    hint {
      human_readable_name = "Code Quality Attestor"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Binary Authorization policy with security enforcement
resource "google_binary_authorization_policy" "security_policy" {
  project = var.project_id
  
  # Default admission rule requiring attestation
  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = var.binauthz_policy_enforcement_mode
    
    require_attestations_by = [
      google_binary_authorization_attestor.quality_attestor.name
    ]
  }
  
  # Global policy evaluation mode
  global_policy_evaluation_mode = "ENABLE"
  
  # Admission whitelist patterns for allowed images
  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.project_id}/allowlisted-*"
  }
  
  depends_on = [
    google_binary_authorization_attestor.quality_attestor
  ]
}

# Create Cloud Build trigger for automated security pipeline
resource "google_cloudbuild_trigger" "security_trigger" {
  name        = local.trigger_name
  description = "Automated security and quality enforcement pipeline"
  project     = var.project_id
  
  # Trigger configuration for Cloud Source Repository
  trigger_template {
    project_id  = var.project_id
    repo_name   = google_sourcerepo_repository.app_repo.name
    branch_name = "main"
  }
  
  # Cloud Build configuration with security scanning steps
  build {
    timeout = var.build_timeout
    
    # Unit testing step
    step {
      name = "python:3.11-slim"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        pip install -r requirements.txt pytest
        python -m pytest tests/ -v || exit 1
        EOT
      ]
      id = "unit-tests"
    }
    
    # Static code analysis with bandit
    step {
      name = "python:3.11-slim"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        pip install bandit[toml]
        bandit -r app/ -f json -o security/bandit-report.json || true
        bandit -r app/ --severity-level medium || exit 1
        EOT
      ]
      id = "static-analysis"
    }
    
    # Dependency vulnerability scanning
    step {
      name = "python:3.11-slim"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        pip install safety
        safety check --json --output security/safety-report.json || true
        safety check --short-report || exit 1
        EOT
      ]
      id = "dependency-scan"
    }
    
    # Build container image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/$PROJECT_ID/${var.container_image_name}:$BUILD_ID",
        "."
      ]
      id = "build-image"
    }
    
    # Push container image for vulnerability scanning
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/$PROJECT_ID/${var.container_image_name}:$BUILD_ID"
      ]
      id = "push-image"
    }
    
    # Create attestation for Binary Authorization
    step {
      name = "gcr.io/cloud-builders/gcloud"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOT
        gcloud container binauthz attestations sign-and-create \
          --artifact-url=gcr.io/$PROJECT_ID/${var.container_image_name}:$BUILD_ID \
          --attestor=${local.attestor_name} \
          --attestor-project=$PROJECT_ID \
          --keyversion=${google_kms_crypto_key.attestor_key.id}/cryptoKeyVersions/1
        EOT
      ]
      id = "create-attestation"
    }
    
    # Build substitutions for dynamic values
    substitutions = {
      _IMAGE_NAME    = var.container_image_name
      _ATTESTOR_NAME = local.attestor_name
    }
    
    # Build options for enhanced security
    options {
      logging = "CLOUD_LOGGING_ONLY"
      
      # Use higher CPU for faster builds
      machine_type = "E2_HIGHCPU_8"
      
      # Enable substitution validation
      substitution_option = "ALLOW_LOOSE"
    }
    
    # Define images to be built
    images = [
      "gcr.io/$PROJECT_ID/${var.container_image_name}:$BUILD_ID"
    ]
  }
  
  # Use the dedicated service account
  service_account = google_service_account.build_service_account.id
  
  depends_on = [
    google_sourcerepo_repository.app_repo,
    google_service_account.build_service_account,
    google_binary_authorization_attestor.quality_attestor,
    google_project_iam_member.build_service_account_roles
  ]
}

# Create GKE cluster with Binary Authorization and security features enabled
resource "google_container_cluster" "security_cluster" {
  name               = var.cluster_name
  location           = var.zone
  project            = var.project_id
  deletion_protection = false
  
  # Remove default node pool to use custom node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Enable Binary Authorization for deployment-time security
  enable_binary_authorization = true
  
  # Enable network policy for pod-to-pod communication control
  network_policy {
    enabled = var.enable_network_policy
  }
  
  # Configure IP allocation for pods and services
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.0.0.0/16"
    services_ipv4_cidr_block = "10.1.0.0/16"
  }
  
  # Enable Workload Identity for secure pod-to-GCP service communication
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }
  
  # Configure master authentication and networking
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  # Security and compliance features
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  
  # Cluster-level resource labels
  resource_labels = local.default_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_binary_authorization_policy.security_policy
  ]
}

# Create custom node pool with security features
resource "google_container_node_pool" "security_nodes" {
  name       = "${var.cluster_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.security_cluster.name
  project    = var.project_id
  node_count = var.node_count
  
  # Node configuration with security hardening
  node_config {
    machine_type = var.node_machine_type
    
    # Use Google Container-Optimized OS
    image_type = "COS_CONTAINERD"
    
    # Enable shielded nodes for additional security
    dynamic "shielded_instance_config" {
      for_each = var.enable_shielded_nodes ? [1] : []
      content {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }
    }
    
    # Service account for nodes
    service_account = google_service_account.build_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Security and compliance metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    # Node labels for workload scheduling
    labels = merge(local.default_labels, {
      role = "security-workload"
    })
    
    # Node taints for dedicated security workloads (optional)
    # taint {
    #   key    = "security-workload"
    #   value  = "true"
    #   effect = "NO_SCHEDULE"
    # }
  }
  
  # Node pool management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }
  
  depends_on = [google_container_cluster.security_cluster]
}

# Create Security Command Center custom source for pipeline findings
resource "google_scc_source" "pipeline_source" {
  display_name = var.scc_source_display_name
  description  = var.scc_source_description
  
  depends_on = [google_project_service.required_apis]
}

# Create sample security finding to demonstrate SCC integration
resource "google_scc_finding" "sample_finding" {
  parent      = "${google_scc_source.pipeline_source.name}/findings/finding-code-quality-001"
  state       = "ACTIVE"
  category    = "SECURITY_SCAN_RESULT"
  external_uri = "https://console.cloud.google.com/cloud-build/builds"
  
  source_properties = {
    scanType   = "container-scan"
    severity   = "medium" 
    pipeline   = local.trigger_name
    created_by = "terraform"
  }
  
  depends_on = [google_scc_source.pipeline_source]
}