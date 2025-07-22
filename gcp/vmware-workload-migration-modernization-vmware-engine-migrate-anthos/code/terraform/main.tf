# Main Terraform configuration for VMware workload migration and modernization
# This file creates the core infrastructure for VMware Engine and GKE migration

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  project_suffix           = random_id.suffix.hex
  private_cloud_name       = var.vmware_private_cloud_name != "" ? var.vmware_private_cloud_name : "vmware-cloud-${local.project_suffix}"
  gke_cluster_name         = var.gke_cluster_name != "" ? var.gke_cluster_name : "modernized-apps-${local.project_suffix}"
  network_name             = var.network_name != "" ? var.network_name : "vmware-network-${local.project_suffix}"
  subnet_name              = "vmware-mgmt-subnet-${local.project_suffix}"
  vmware_engine_network    = "${local.private_cloud_name}-network"
  artifact_registry_name   = "${var.artifact_registry_name}-${local.project_suffix}"
  monitoring_dashboard_name = "${var.monitoring_dashboard_name}-${local.project_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    project     = var.organization_name
    environment = var.environment
    managed-by  = "terraform"
    created-by  = "vmware-migration-recipe"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "vmwareengine.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "binaryauthorization.googleapis.com",
    "servicenetworking.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC network for VMware Engine and GKE connectivity
resource "google_compute_network" "vmware_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC network for VMware Engine and GKE connectivity"

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create subnet for VMware Engine management and GKE nodes
resource "google_compute_subnetwork" "vmware_mgmt_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vmware_network.id
  description   = "Subnet for VMware Engine management and GKE nodes"

  # Secondary IP ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.secondary_pod_range
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.secondary_service_range
  }

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for VMware HCX and management traffic
resource "google_compute_firewall" "allow_vmware_hcx" {
  name    = "allow-vmware-hcx-${local.project_suffix}"
  network = google_compute_network.vmware_network.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8043", "9443"]
  }

  allow {
    protocol = "udp"
    ports    = ["500", "4500"]
  }

  source_ranges = ["10.0.0.0/8", "192.168.0.0/16", var.vmware_management_range]
  target_tags   = ["vmware-hcx"]

  description = "Allow VMware HCX traffic for workload migration"
}

# Create firewall rules for GKE cluster communication
resource "google_compute_firewall" "allow_gke_webhooks" {
  name    = "allow-gke-webhooks-${local.project_suffix}"
  network = google_compute_network.vmware_network.name

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "15017"]
  }

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = ["gke-node"]

  description = "Allow GKE master to communicate with node webhooks"
}

# Create VPN gateway for on-premises connectivity
resource "google_compute_vpn_gateway" "vmware_vpn_gateway" {
  name    = "vmware-vpn-gateway-${local.project_suffix}"
  network = google_compute_network.vmware_network.id
  region  = var.region

  description = "VPN gateway for on-premises VMware environment connectivity"
}

# Create VMware Engine private cloud
resource "google_vmwareengine_private_cloud" "vmware_private_cloud" {
  provider    = google-beta
  location    = var.vmware_engine_region
  name        = local.private_cloud_name
  description = "VMware Engine private cloud for workload migration"

  # Management cluster configuration
  management_cluster {
    cluster_id = "initial-cluster"
    
    node_type_configs {
      node_type_id = var.vmware_node_type
      node_count   = var.vmware_node_count
    }
  }

  # Network configuration
  network_config {
    management_cidr       = var.vmware_management_range
    vmware_engine_network = local.vmware_engine_network
  }

  # Wait for API enablement
  depends_on = [
    google_project_service.required_apis,
    google_compute_network.vmware_network
  ]

  # This can take 30-45 minutes to provision
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# Create VMware Engine network for private cloud
resource "google_vmwareengine_network" "vmware_engine_network" {
  provider    = google-beta
  location    = var.vmware_engine_region
  name        = local.vmware_engine_network
  type        = "STANDARD"
  description = "VMware Engine network for private cloud connectivity"

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "modernized_apps" {
  location      = var.region
  repository_id = local.artifact_registry_name
  description   = "Repository for modernized application containers"
  format        = var.artifact_registry_format

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create GKE cluster for modernized applications
resource "google_container_cluster" "modernized_apps_cluster" {
  name     = local.gke_cluster_name
  location = var.region

  description = "GKE cluster for modernized VMware applications"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = google_compute_network.vmware_network.id
  subnetwork = google_compute_subnetwork.vmware_mgmt_subnet.id

  # Enable IP aliasing for better networking
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Enable private nodes for security
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Master authorized networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_cidr
      display_name = "VPC subnet"
    }
    cidr_blocks {
      cidr_block   = var.vmware_management_range
      display_name = "VMware management network"
    }
  }

  # Enable network policy
  network_policy {
    enabled = var.enable_network_policy
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable binary authorization
  binary_authorization {
    enabled = var.enable_binary_authorization
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    
    managed_prometheus {
      enabled = true
    }
  }

  # Enable auto-upgrade and auto-repair
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Security configuration
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  # Resource labels
  resource_labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.vmware_mgmt_subnet
  ]
}

# Create GKE node pool for modernized applications
resource "google_container_node_pool" "modernized_apps_nodes" {
  name       = "modernized-apps-nodes"
  location   = var.region
  cluster    = google_container_cluster.modernized_apps_cluster.name
  node_count = var.gke_node_count

  # Auto-scaling configuration
  autoscaling {
    min_node_count = var.gke_min_node_count
    max_node_count = var.gke_max_node_count
  }

  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_disk_size_gb
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    # Enable secure boot and integrity monitoring
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Service account with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels and tags
    labels = local.common_labels
    tags   = ["gke-node"]

    # Workload metadata configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # Auto-upgrade and auto-repair
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Create service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes-${local.project_suffix}"
  display_name = "GKE Nodes Service Account"
  description  = "Service account for GKE nodes in modernized applications cluster"
}

# Assign necessary roles to GKE nodes service account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Create service account for Migrate to Containers
resource "google_service_account" "migrate_to_containers" {
  account_id   = "migrate-to-containers-${local.project_suffix}"
  display_name = "Migrate to Containers Service Account"
  description  = "Service account for Migrate to Containers operations"
}

# Assign roles to Migrate to Containers service account
resource "google_project_iam_member" "migrate_to_containers_roles" {
  for_each = toset([
    "roles/compute.admin",
    "roles/container.admin",
    "roles/artifactregistry.admin",
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.migrate_to_containers.email}"
}

# Create monitoring workspace (if it doesn't exist)
resource "google_monitoring_monitored_project" "primary" {
  count = var.enable_monitoring ? 1 : 0

  metrics_scope = var.project_id
  name          = var.project_id
}

# Create monitoring dashboard for hybrid infrastructure
resource "google_monitoring_dashboard" "hybrid_infrastructure" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = local.monitoring_dashboard_name
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "VMware Engine Resource Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"vmware_vcenter\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "GKE Container Performance"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"k8s_container\" resource.label.cluster_name=\"${local.gke_cluster_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Network Traffic"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_subnetwork\" resource.label.subnetwork_name=\"${local.subnet_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_project_service.required_apis,
    google_monitoring_monitored_project.primary
  ]
}

# Create alerting policy for critical infrastructure events
resource "google_monitoring_alert_policy" "hybrid_infrastructure_alerts" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Hybrid Infrastructure Alerts"
  combiner     = "OR"

  conditions {
    display_name = "High VMware CPU Usage"
    
    condition_threshold {
      filter         = "resource.type=\"vmware_vcenter\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      duration       = "300s"
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  conditions {
    display_name = "GKE Pod Failures"
    
    condition_threshold {
      filter         = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      duration       = "300s"
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_monitoring_monitored_project.primary
  ]
}

# Create log sink for security monitoring
resource "google_logging_project_sink" "security_sink" {
  name = "security-sink-${local.project_suffix}"

  # Can export to pubsub, cloud storage, or bigquery
  destination = "storage.googleapis.com/${google_storage_bucket.security_logs.name}"

  # Log filter for security events
  filter = <<EOF
protoPayload.serviceName="vmwareengine.googleapis.com" OR
protoPayload.serviceName="container.googleapis.com" OR
protoPayload.serviceName="binaryauthorization.googleapis.com" OR
severity>=ERROR
EOF

  # Use a unique writer for the sink
  unique_writer_identity = true
}

# Create storage bucket for security logs
resource "google_storage_bucket" "security_logs" {
  name          = "security-logs-${local.project_suffix}"
  location      = var.region
  force_destroy = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.security_logs_key.id
  }

  labels = local.common_labels
}

# Create KMS key for security logs encryption
resource "google_kms_key_ring" "security_logs_keyring" {
  name     = "security-logs-keyring-${local.project_suffix}"
  location = var.region

  depends_on = [
    google_project_service.required_apis
  ]
}

resource "google_kms_crypto_key" "security_logs_key" {
  name            = "security-logs-key"
  key_ring        = google_kms_key_ring.security_logs_keyring.id
  rotation_period = "100000s"

  lifecycle {
    prevent_destroy = true
  }
}

# Grant the log sink service account access to the storage bucket
resource "google_storage_bucket_iam_member" "security_logs_sink" {
  bucket = google_storage_bucket.security_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.security_sink.writer_identity
}

# Create budget alert for cost management
resource "google_billing_budget" "vmware_migration_budget" {
  count = var.enable_cost_management ? 1 : 0

  billing_account = data.google_billing_account.account.id
  display_name    = "VMware Migration Budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = var.budget_threshold_percent / 100
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}

# Get billing account information
data "google_billing_account" "account" {
  billing_account = var.project_id
}

# Create namespace for modernized applications
resource "google_service_account" "modernized_apps_workload_identity" {
  account_id   = "modernized-apps-wi-${local.project_suffix}"
  display_name = "Modernized Apps Workload Identity"
  description  = "Service account for modernized applications workload identity"
}

# Create IAM policy binding for workload identity
resource "google_service_account_iam_binding" "modernized_apps_workload_identity" {
  service_account_id = google_service_account.modernized_apps_workload_identity.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[modernized-apps/modernized-apps-ksa]"
  ]
}

# Add delay to allow private cloud to be fully provisioned
resource "time_sleep" "wait_for_private_cloud" {
  depends_on = [google_vmwareengine_private_cloud.vmware_private_cloud]

  create_duration = "10m"
}