# Main Terraform configuration for Privacy-Preserving Analytics
# with Confidential GKE and BigQuery
#
# This configuration creates a complete privacy-preserving analytics platform
# using Google Cloud's Confidential Computing technologies, including:
# - Confidential GKE cluster with hardware-based memory encryption
# - BigQuery with Customer-Managed Encryption Keys (CMEK)
# - Cloud KMS for encryption key management
# - Cloud Storage for ML training data
# - Vertex AI integration for privacy-preserving machine learning

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources if not provided
  cluster_name  = var.cluster_name != null ? var.cluster_name : "confidential-cluster-${random_id.suffix.hex}"
  keyring_name  = var.keyring_name != null ? var.keyring_name : "analytics-keyring-${random_id.suffix.hex}"
  key_name      = var.key_name != null ? var.key_name : "analytics-key-${random_id.suffix.hex}"
  dataset_name  = var.dataset_name != null ? var.dataset_name : "sensitive_analytics_${random_id.suffix.hex}"
  bucket_name   = var.bucket_name != null ? var.bucket_name : "privacy-analytics-${var.project_id}-${random_id.suffix.hex}"

  # Common labels for all resources
  common_labels = merge(var.resource_labels, {
    terraform-managed = "true"
    recipe-name      = "privacy-preserving-analytics-confidential-gke-bigquery"
  })
}

#####################################################################
# Enable Required APIs
#####################################################################

resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",           # GKE
    "bigquery.googleapis.com",           # BigQuery
    "cloudkms.googleapis.com",           # Cloud KMS
    "aiplatform.googleapis.com",         # Vertex AI
    "compute.googleapis.com",            # Compute Engine
    "storage.googleapis.com",            # Cloud Storage
    "logging.googleapis.com",            # Cloud Logging
    "monitoring.googleapis.com",         # Cloud Monitoring
    "cloudresourcemanager.googleapis.com", # Resource Manager
    "iam.googleapis.com",                # IAM
    "secretmanager.googleapis.com"       # Secret Manager
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    read   = "5m"
  }
}

#####################################################################
# Networking Resources
#####################################################################

# Create VPC network for the cluster
resource "google_compute_network" "confidential_vpc" {
  name                    = "confidential-analytics-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  mtu                     = 1460
  project                 = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create subnet for GKE cluster
resource "google_compute_subnetwork" "confidential_subnet" {
  name          = "confidential-analytics-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.confidential_vpc.id
  project       = var.project_id

  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = var.pods_secondary_range_name
    ip_cidr_range = var.pods_secondary_range_cidr
  }

  secondary_ip_range {
    range_name    = var.services_secondary_range_name
    ip_cidr_range = var.services_secondary_range_cidr
  }

  # Enable private Google access for nodes without external IPs
  private_ip_google_access = true

  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for GKE cluster
resource "google_compute_firewall" "confidential_firewall" {
  name    = "confidential-analytics-firewall-${random_id.suffix.hex}"
  network = google_compute_network.confidential_vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080", "8443"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  target_tags   = ["gke-node", "confidential-analytics"]

  depends_on = [google_compute_network.confidential_vpc]
}

# Router for NAT gateway (required for private nodes)
resource "google_compute_router" "confidential_router" {
  name    = "confidential-analytics-router-${random_id.suffix.hex}"
  region  = var.region
  network = google_compute_network.confidential_vpc.id
  project = var.project_id

  bgp {
    asn = 64514
  }
}

# NAT gateway for outbound internet access from private nodes
resource "google_compute_router_nat" "confidential_nat" {
  name                               = "confidential-analytics-nat-${random_id.suffix.hex}"
  router                             = google_compute_router.confidential_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#####################################################################
# Cloud KMS Encryption Keys
#####################################################################

# Create KMS key ring for analytics encryption
resource "google_kms_key_ring" "analytics_keyring" {
  name     = local.keyring_name
  location = var.region
  project  = var.project_id

  depends_on = [google_project_service.required_apis]

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# Create symmetric encryption key for data protection
resource "google_kms_crypto_key" "analytics_key" {
  name     = local.key_name
  key_ring = google_kms_key_ring.analytics_keyring.id

  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = "7776000s" # 90 days

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = false # Set to true in production
  }

  labels = local.common_labels
}

# IAM binding for GKE service account to use the encryption key
resource "google_kms_crypto_key_iam_binding" "gke_key_binding" {
  crypto_key_id = google_kms_crypto_key.analytics_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com",
    "serviceAccount:${google_service_account.gke_service_account.email}",
  ]

  depends_on = [google_kms_crypto_key.analytics_key]
}

# IAM binding for BigQuery service account to use the encryption key
resource "google_kms_crypto_key_iam_binding" "bigquery_key_binding" {
  crypto_key_id = google_kms_crypto_key.analytics_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:bq-${data.google_project.current.number}@bigquery-encryption.iam.gserviceaccount.com",
  ]

  depends_on = [google_kms_crypto_key.analytics_key]
}

# IAM binding for Cloud Storage service account to use the encryption key
resource "google_kms_crypto_key_iam_binding" "storage_key_binding" {
  crypto_key_id = google_kms_crypto_key.analytics_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com",
  ]

  depends_on = [google_kms_crypto_key.analytics_key]
}

#####################################################################
# Service Accounts and IAM
#####################################################################

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Service account for GKE nodes
resource "google_service_account" "gke_service_account" {
  account_id   = "confidential-gke-sa-${random_id.suffix.hex}"
  display_name = "Confidential GKE Service Account"
  description  = "Service account for Confidential GKE cluster nodes"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for GKE service account
resource "google_project_iam_member" "gke_node_service_account" {
  for_each = toset([
    "roles/container.nodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
    "roles/bigquery.jobUser",
    "roles/bigquery.dataViewer",
    "roles/aiplatform.user"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_service_account.email}"

  depends_on = [google_service_account.gke_service_account]
}

# Service account for analytics applications
resource "google_service_account" "analytics_service_account" {
  account_id   = "privacy-analytics-sa-${random_id.suffix.hex}"
  display_name = "Privacy Analytics Service Account"
  description  = "Service account for privacy-preserving analytics applications"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for analytics service account
resource "google_project_iam_member" "analytics_service_account" {
  for_each = toset([
    "roles/bigquery.admin",
    "roles/storage.admin",
    "roles/aiplatform.admin",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.analytics_service_account.email}"

  depends_on = [google_service_account.analytics_service_account]
}

# Workload Identity binding
resource "google_service_account_iam_binding" "workload_identity_binding" {
  count = var.enable_workload_identity ? 1 : 0

  service_account_id = google_service_account.analytics_service_account.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[default/privacy-analytics-app]",
  ]

  depends_on = [google_service_account.analytics_service_account]
}

#####################################################################
# Confidential GKE Cluster
#####################################################################

# Create Confidential GKE cluster with hardware encryption
resource "google_container_cluster" "confidential_cluster" {
  name     = local.cluster_name
  location = var.zone
  project  = var.project_id

  # Cluster configuration
  min_master_version = var.kubernetes_version != "latest" ? var.kubernetes_version : null
  initial_node_count = 1
  remove_default_node_pool = true

  # Network configuration
  network    = google_compute_network.confidential_vpc.self_link
  subnetwork = google_compute_subnetwork.confidential_subnet.self_link

  # IP allocation policy for alias IPs
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = !var.enable_private_endpoint
    }
  }

  # Workload Identity configuration
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  # Network policy
  dynamic "network_policy" {
    for_each = var.enable_network_policy ? [1] : []
    content {
      enabled  = true
      provider = "CALICO"
    }
  }

  # Enable network policy addon
  addons_config {
    network_policy_config {
      disabled = !var.enable_network_policy
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    http_load_balancing {
      disabled = false
    }

    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # Confidential nodes configuration
  confidential_nodes {
    enabled = true
  }

  # Security configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  # Binary Authorization (optional)
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Cluster resource labels
  resource_labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.confidential_subnet,
    google_service_account.gke_service_account
  ]

  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_pool
    ]
  }
}

# Create node pool with confidential computing
resource "google_container_node_pool" "confidential_nodes" {
  name       = "confidential-node-pool-${random_id.suffix.hex}"
  location   = var.zone
  cluster    = google_container_cluster.confidential_cluster.name
  project    = var.project_id

  # Node count and autoscaling
  initial_node_count = var.node_count
  
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  # Node configuration
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    preemptible  = var.preemptible

    # Confidential computing configuration
    confidential_nodes {
      enabled = true
    }

    # Enable AMD SEV or Intel TDX encryption
    advanced_machine_features {
      enable_nested_virtualization = false
    }

    # Service account
    service_account = google_service_account.gke_service_account.email
    oauth_scopes    = var.oauth_scopes

    # Disk encryption with customer-managed key
    disk_encryption_key_id = google_kms_crypto_key.analytics_key.id

    # Node labels and tags
    labels = merge(local.common_labels, {
      "confidential-computing" = "enabled"
      "node-type"             = "confidential"
    })

    tags = ["gke-node", "confidential-analytics"]

    # Security configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload metadata configuration
    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }

    # Node metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }

  # Management settings
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [
    google_container_cluster.confidential_cluster,
    google_kms_crypto_key.analytics_key,
    google_kms_crypto_key_iam_binding.gke_key_binding
  ]

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

#####################################################################
# BigQuery Dataset with CMEK Encryption
#####################################################################

# Create BigQuery dataset with customer-managed encryption
resource "google_bigquery_dataset" "sensitive_analytics" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.region
  description = "Privacy-preserving analytics dataset with CMEK encryption"

  # Customer-managed encryption key
  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.analytics_key.id
  }

  # Access control
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.default.client_email
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  # Labels
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key.analytics_key,
    google_kms_crypto_key_iam_binding.bigquery_key_binding
  ]

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# Create patient analytics table
resource "google_bigquery_table" "patient_analytics" {
  count = var.create_sample_data ? 1 : 0

  dataset_id = google_bigquery_dataset.sensitive_analytics.dataset_id
  table_id   = "patient_analytics"
  project    = var.project_id

  description = "Encrypted healthcare analytics table"

  schema = jsonencode([
    {
      name = "patient_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique patient identifier"
    },
    {
      name = "age"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Patient age"
    },
    {
      name = "diagnosis"
      type = "STRING"
      mode = "NULLABLE"
      description = "Primary diagnosis"
    },
    {
      name = "treatment_cost"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Treatment cost in USD"
    },
    {
      name = "region"
      type = "STRING"
      mode = "NULLABLE"
      description = "Geographic region"
    },
    {
      name = "admission_date"
      type = "DATE"
      mode = "NULLABLE"
      description = "Date of admission"
    }
  ])

  # Encryption configuration inherited from dataset
  encryption_configuration {
    kms_key_name = google_kms_crypto_key.analytics_key.id
  }

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.sensitive_analytics]
}

# Create privacy-preserving analytics view
resource "google_bigquery_table" "privacy_analytics_summary" {
  dataset_id = google_bigquery_dataset.sensitive_analytics.dataset_id
  table_id   = "privacy_analytics_summary"
  project    = var.project_id

  description = "Privacy-preserving analytics view with k-anonymity"

  view {
    query = templatefile("${path.module}/sql/privacy_analytics_summary.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.patient_analytics]
}

# Create compliance report view
resource "google_bigquery_table" "compliance_report" {
  dataset_id = google_bigquery_dataset.sensitive_analytics.dataset_id
  table_id   = "compliance_report"
  project    = var.project_id

  description = "Compliance and encryption status report"

  view {
    query = templatefile("${path.module}/sql/compliance_report.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.patient_analytics]
}

#####################################################################
# Cloud Storage for ML Training Data
#####################################################################

# Create Cloud Storage bucket with encryption
resource "google_storage_bucket" "ml_training_data" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  # Storage class for cost optimization
  storage_class = "STANDARD"

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # Customer-managed encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.analytics_key.id
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Public access prevention
  public_access_prevention = "enforced"

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key.analytics_key,
    google_kms_crypto_key_iam_binding.storage_key_binding
  ]

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# IAM binding for analytics service account to access storage
resource "google_storage_bucket_iam_binding" "analytics_storage_access" {
  bucket = google_storage_bucket.ml_training_data.name
  role   = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.analytics_service_account.email}",
  ]

  depends_on = [google_storage_bucket.ml_training_data]
}

#####################################################################
# Kubernetes Resources
#####################################################################

# Kubernetes namespace for analytics applications
resource "kubernetes_namespace" "analytics" {
  count = var.deploy_sample_application ? 1 : 0

  metadata {
    name = "privacy-analytics"
    labels = merge(local.common_labels, {
      "confidential-computing" = "enabled"
    })
  }

  depends_on = [google_container_cluster.confidential_cluster]
}

# Kubernetes service account with Workload Identity
resource "kubernetes_service_account" "analytics_app" {
  count = var.deploy_sample_application && var.enable_workload_identity ? 1 : 0

  metadata {
    name      = "privacy-analytics-app"
    namespace = kubernetes_namespace.analytics[0].metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.analytics_service_account.email
    }
    labels = local.common_labels
  }

  depends_on = [
    kubernetes_namespace.analytics,
    google_service_account.analytics_service_account
  ]
}

# ConfigMap for application configuration
resource "kubernetes_config_map" "analytics_config" {
  count = var.deploy_sample_application ? 1 : 0

  metadata {
    name      = "analytics-config"
    namespace = kubernetes_namespace.analytics[0].metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "DATASET_NAME"         = "${var.project_id}:${local.dataset_name}"
    "GOOGLE_CLOUD_PROJECT" = var.project_id
    "BUCKET_NAME"          = local.bucket_name
    "ENCRYPTION_KEY"       = google_kms_crypto_key.analytics_key.id
  }

  depends_on = [kubernetes_namespace.analytics]
}

# Deployment for privacy-preserving analytics application
resource "kubernetes_deployment" "analytics_app" {
  count = var.deploy_sample_application ? 1 : 0

  metadata {
    name      = "privacy-analytics-app"
    namespace = kubernetes_namespace.analytics[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "privacy-analytics"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, {
          app = "privacy-analytics"
        })
      }

      spec {
        service_account_name = var.enable_workload_identity ? kubernetes_service_account.analytics_app[0].metadata[0].name : "default"

        container {
          name  = "analytics-processor"
          image = "python:3.11-slim"

          command = ["/bin/bash"]
          args = [
            "-c",
            <<-EOT
              pip install --no-cache-dir google-cloud-bigquery==3.11.4 google-cloud-kms==2.21.0
              python -c "
              from google.cloud import bigquery
              import os
              import time
              import logging
              
              # Configure logging
              logging.basicConfig(level=logging.INFO)
              logger = logging.getLogger(__name__)
              
              # Initialize BigQuery client
              client = bigquery.Client()
              dataset_id = os.environ['DATASET_NAME']
              
              logger.info(f'Starting privacy-preserving analytics for dataset: {dataset_id}')
              
              while True:
                  try:
                      logger.info('Processing encrypted analytics...')
                      
                      # Execute privacy-preserving query with aggregation
                      query = f'''
                      SELECT 
                          diagnosis,
                          region,
                          COUNT(*) as patient_count,
                          AVG(age) as avg_age,
                          AVG(treatment_cost) as avg_cost,
                          STDDEV(treatment_cost) as cost_stddev
                      FROM \`{dataset_id}.patient_analytics\`
                      WHERE admission_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                      GROUP BY diagnosis, region
                      HAVING COUNT(*) >= 5
                      ORDER BY patient_count DESC
                      '''
                      
                      results = client.query(query)
                      logger.info('Analytics results (encrypted processing):')
                      for row in results:
                          logger.info(f'  {row.diagnosis} in {row.region}: {row.patient_count} patients, '
                                    f'avg age {row.avg_age:.1f}, avg cost ${row.avg_cost:.2f}')
                  except Exception as e:
                      logger.error(f'Analytics error: {e}')
                  
                  time.sleep(60)  # Process every minute
              "
            EOT
          ]

          env_from {
            config_map_ref {
              name = kubernetes_config_map.analytics_config[0].metadata[0].name
            }
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root           = true
            run_as_user               = 65534
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 65534
          fs_group        = 65534
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.analytics,
    kubernetes_config_map.analytics_config,
    google_bigquery_dataset.sensitive_analytics
  ]
}

# Service for analytics application
resource "kubernetes_service" "analytics_service" {
  count = var.deploy_sample_application ? 1 : 0

  metadata {
    name      = "privacy-analytics-service"
    namespace = kubernetes_namespace.analytics[0].metadata[0].name
    labels    = local.common_labels
  }

  spec {
    selector = {
      app = "privacy-analytics"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.analytics_app]
}

#####################################################################
# Sample Data Population (Optional)
#####################################################################

# Populate sample healthcare data
resource "null_resource" "populate_sample_data" {
  count = var.create_sample_data ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      gcloud auth application-default print-access-token > /tmp/access_token
      
      bq query --use_legacy_sql=false \
        --destination_table=${var.project_id}:${local.dataset_name}.patient_analytics \
        --replace \
        --format=none \
        "SELECT 
            CONCAT('PATIENT_', LPAD(CAST(ROW_NUMBER() OVER() AS STRING), 6, '0')) as patient_id,
            CAST(RAND() * 80 + 20 AS INT64) as age,
            CASE CAST(RAND() * 5 AS INT64)
                WHEN 0 THEN 'Diabetes'
                WHEN 1 THEN 'Hypertension' 
                WHEN 2 THEN 'Heart Disease'
                WHEN 3 THEN 'Cancer'
                ELSE 'Respiratory Disease'
            END as diagnosis,
            ROUND(RAND() * 50000 + 5000, 2) as treatment_cost,
            CASE CAST(RAND() * 4 AS INT64)
                WHEN 0 THEN 'North'
                WHEN 1 THEN 'South'
                WHEN 2 THEN 'East'
                ELSE 'West'
            END as region,
            DATE_SUB(CURRENT_DATE(), INTERVAL CAST(RAND() * 365 AS INT64) DAY) as admission_date
        FROM UNNEST(GENERATE_ARRAY(1, 10000)) as num"
    EOT

    environment = {
      GOOGLE_CLOUD_PROJECT = var.project_id
    }
  }

  depends_on = [
    google_bigquery_table.patient_analytics,
    google_kms_crypto_key_iam_binding.bigquery_key_binding
  ]

  triggers = {
    dataset_id = google_bigquery_dataset.sensitive_analytics.dataset_id
    table_id   = var.create_sample_data ? google_bigquery_table.patient_analytics[0].table_id : ""
  }
}