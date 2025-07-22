# Random suffix for resource naming to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  name_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.resource_labels, {
    terraform-managed = "true"
    creation-date     = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Cluster configurations with computed names
  clusters_config = {
    for env, config in var.clusters : env => merge(config, {
      full_name = "${var.resource_prefix}-${config.name}-${local.name_suffix}"
    })
  }
  
  # Required APIs for the solution
  required_apis = [
    "container.googleapis.com",
    "mesh.googleapis.com", 
    "gkehub.googleapis.com",
    "sourcerepo.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Wait for APIs to be fully enabled before proceeding
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create VPC network for the clusters
resource "google_compute_network" "service_mesh_network" {
  name                    = "${var.network_name}-${local.name_suffix}"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create subnet for the clusters with secondary ranges for pods and services
resource "google_compute_subnetwork" "service_mesh_subnet" {
  name                     = "${var.subnet_name}-${local.name_suffix}"
  ip_cidr_range           = var.subnet_cidr
  region                  = var.region
  network                 = google_compute_network.service_mesh_network.id
  private_ip_google_access = true
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for service mesh communication
resource "google_compute_firewall" "service_mesh_internal" {
  name    = "allow-service-mesh-internal-${local.name_suffix}"
  network = google_compute_network.service_mesh_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["15010", "15011", "15014", "15017", "15021", "8080", "9090", "9091", "9901", "9902", "9903"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
  target_tags   = ["gke-node"]
  
  description = "Allow service mesh internal communication"
}

# Create Artifact Registry repository for secure container images
resource "google_artifact_registry_repository" "secure_apps" {
  count = var.enable_binary_authorization ? 1 : 0
  
  location      = var.region
  repository_id = "${var.artifact_registry_repository}-${local.name_suffix}"
  description   = "Repository for secure container images with Binary Authorization"
  format        = var.artifact_registry_format
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create GKE clusters for each environment
resource "google_container_cluster" "service_mesh_clusters" {
  for_each = local.clusters_config
  
  name     = each.value.full_name
  location = var.zone
  
  # Network configuration
  network    = google_compute_network.service_mesh_network.name
  subnetwork = google_compute_subnetwork.service_mesh_subnet.name
  
  # Remove default node pool immediately after cluster creation
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Cluster networking configuration
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Workload Identity configuration
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Network policy configuration
  network_policy {
    enabled  = var.enable_network_policy
    provider = var.enable_network_policy ? "CALICO" : null
  }
  
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = !var.enable_network_policy
    }
    
    dns_cache_config {
      enabled = true
    }
  }
  
  # Pod security policy configuration
  dynamic "pod_security_policy_config" {
    for_each = var.enable_pod_security_policy ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Binary Authorization configuration
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
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
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
    
    master_global_access_config {
      enabled = true
    }
  }
  
  # Cluster resource labels
  resource_labels = merge(local.common_labels, each.value.labels)
  
  # Monitoring and logging configuration
  monitoring_config {
    enable_components = var.enable_monitoring ? [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER"
    ] : []
    
    managed_prometheus {
      enabled = var.enable_monitoring
    }
  }
  
  logging_config {
    enable_components = var.enable_logging ? [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER"
    ] : []
  }
  
  # Cluster autoscaling configuration
  dynamic "cluster_autoscaling" {
    for_each = var.enable_cluster_autoscaling ? [1] : []
    content {
      enabled = true
      resource_limits {
        resource_type = "cpu"
        minimum       = 1
        maximum       = 100
      }
      resource_limits {
        resource_type = "memory"
        minimum       = 2
        maximum       = 1000
      }
      auto_provisioning_defaults {
        oauth_scopes = [
          "https://www.googleapis.com/auth/cloud-platform"
        ]
        management {
          auto_repair  = var.node_auto_repair
          auto_upgrade = var.node_auto_upgrade
        }
      }
    }
  }
  
  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T03:00:00Z"
      end_time   = "2023-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }
  
  # Node configuration defaults
  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  depends_on = [
    google_compute_subnetwork.service_mesh_subnet,
    google_project_service.required_apis,
    time_sleep.wait_for_apis
  ]
  
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "gke-nodes-${local.name_suffix}"
  display_name = "GKE Nodes Service Account"
  description  = "Service account for GKE nodes in service mesh governance solution"
}

# Assign necessary IAM roles to the GKE nodes service account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/container.nodeServiceAccount"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Create managed node pools for each cluster
resource "google_container_node_pool" "service_mesh_node_pools" {
  for_each = local.clusters_config
  
  name       = "${each.value.full_name}-nodes"
  location   = var.zone
  cluster    = google_container_cluster.service_mesh_clusters[each.key].name
  
  node_count = each.value.num_nodes
  
  autoscaling {
    min_node_count = 1
    max_node_count = each.value.num_nodes * 2
  }
  
  management {
    auto_repair  = var.node_auto_repair
    auto_upgrade = var.node_auto_upgrade
  }
  
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  
  node_config {
    preemptible  = var.enable_preemptible_nodes && each.value.environment != "production"
    machine_type = each.value.machine_type
    disk_size_gb = 100
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"
    
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    labels = merge(local.common_labels, each.value.labels)
    
    tags = ["gke-node", "${each.value.environment}-node"]
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Taint non-production nodes to optimize cost
    dynamic "taint" {
      for_each = var.enable_preemptible_nodes && each.value.environment != "production" ? [1] : []
      content {
        key    = "preemptible"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }
  }
  
  depends_on = [
    google_container_cluster.service_mesh_clusters,
    google_project_iam_member.gke_nodes_roles
  ]
  
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Create GKE Hub memberships for fleet management
resource "google_gke_hub_membership" "cluster_memberships" {
  for_each = local.clusters_config
  
  membership_id = "${each.value.environment}-membership-${local.name_suffix}"
  
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.service_mesh_clusters[each.key].id}"
    }
  }
  
  authority {
    issuer = "https://container.googleapis.com/v1/${google_container_cluster.service_mesh_clusters[each.key].id}"
  }
  
  labels = merge(local.common_labels, {
    environment = each.value.environment
    mesh        = "enabled"
  })
  
  depends_on = [
    google_container_cluster.service_mesh_clusters,
    google_container_node_pool.service_mesh_node_pools
  ]
}

# Enable Anthos Service Mesh on the fleet
resource "google_gke_hub_feature" "service_mesh" {
  count = var.enable_anthos_service_mesh ? 1 : 0
  
  name     = "servicemesh"
  location = "global"
  
  depends_on = [google_gke_hub_membership.cluster_memberships]
}

# Configure Service Mesh for each cluster membership
resource "google_gke_hub_feature_membership" "service_mesh_memberships" {
  for_each = var.enable_anthos_service_mesh ? local.clusters_config : {}
  
  location   = "global"
  feature    = google_gke_hub_feature.service_mesh[0].name
  membership = google_gke_hub_membership.cluster_memberships[each.key].membership_id
  
  mesh {
    management = "MANAGEMENT_AUTOMATIC"
    control_plane = "AUTOMATIC"
  }
  
  depends_on = [google_gke_hub_feature.service_mesh]
}

# Enable Config Management on the fleet
resource "google_gke_hub_feature" "config_management" {
  count = var.enable_config_management ? 1 : 0
  
  name     = "configmanagement"
  location = "global"
  
  depends_on = [google_gke_hub_membership.cluster_memberships]
}

# Configure Config Management for each cluster membership
resource "google_gke_hub_feature_membership" "config_management_memberships" {
  for_each = var.enable_config_management ? local.clusters_config : {}
  
  location   = "global"
  feature    = google_gke_hub_feature.config_management[0].name
  membership = google_gke_hub_membership.cluster_memberships[each.key].membership_id
  
  configmanagement {
    version = "1.15.1"
    
    config_sync {
      source_format = "unstructured"
      
      git {
        sync_repo   = var.config_sync_git_repo != "" ? var.config_sync_git_repo : "https://source.developers.google.com/p/${var.project_id}/r/anthos-config-management"
        sync_branch = var.config_sync_git_branch
        policy_dir  = var.config_sync_policy_dir
        secret_type = "none"
      }
    }
    
    policy_controller {
      enabled                    = true
      template_library_installed = true
      audit_interval_seconds     = 60
      exemptable_namespaces      = ["kube-system", "istio-system", "config-management-system"]
      log_denies_enabled         = true
      referential_rules_enabled  = true
    }
  }
  
  depends_on = [google_gke_hub_feature.config_management]
}

# Create Binary Authorization policy for container security
resource "google_binary_authorization_policy" "policy" {
  count = var.enable_binary_authorization ? 1 : 0
  
  # Default admission rule - deny all by default
  default_admission_rule {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = var.binary_auth_enforcement_mode
  }
  
  # Admission whitelist patterns for system images
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "k8s.gcr.io/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gke.gcr.io/*"
  }
  
  admission_whitelist_patterns {
    name_pattern = "gcr.io/stackdriver-agents/*"
  }
  
  # Cluster-specific admission rules
  dynamic "cluster_admission_rules" {
    for_each = local.clusters_config
    content {
      cluster          = google_container_cluster.service_mesh_clusters[cluster_admission_rules.key].id
      evaluation_mode  = "REQUIRE_ATTESTATION"
      enforcement_mode = var.binary_auth_enforcement_mode
      
      require_attestations_by = [
        google_binary_authorization_attestor.attestors[cluster_admission_rules.value.environment].name
      ]
    }
  }
  
  depends_on = [google_container_cluster.service_mesh_clusters]
}

# Create attestors for Binary Authorization
resource "google_binary_authorization_attestor" "attestors" {
  for_each = var.enable_binary_authorization ? local.clusters_config : {}
  
  name = "${each.value.environment}-attestor-${local.name_suffix}"
  
  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_notes[each.key].name
    
    public_keys {
      ascii_armored_pgp_public_key = tls_private_key.attestor_keys[each.key].public_key_pem
    }
  }
  
  description = "Attestor for ${each.value.environment} environment"
}

# Create Container Analysis notes for attestors
resource "google_container_analysis_note" "attestor_notes" {
  for_each = var.enable_binary_authorization ? local.clusters_config : {}
  
  name = "${each.value.environment}-note-${local.name_suffix}"
  
  attestation_authority {
    hint {
      human_readable_name = "${each.value.environment} attestor"
    }
  }
  
  short_description = "Container analysis note for ${each.value.environment} environment"
  long_description  = "This note is used by Binary Authorization to attest container images for the ${each.value.environment} environment in the service mesh governance solution."
}

# Generate private keys for attestors
resource "tls_private_key" "attestor_keys" {
  for_each = var.enable_binary_authorization ? local.clusters_config : {}
  
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create Source Repository for Config Management (if Git repo not provided)
resource "google_sourcerepo_repository" "config_management_repo" {
  count = var.enable_config_management && var.config_sync_git_repo == "" ? 1 : 0
  
  name = "anthos-config-management-${local.name_suffix}"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create monitoring dashboard for service mesh observability
resource "google_monitoring_dashboard" "service_mesh_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Service Mesh Governance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Service Mesh Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    prometheusQuery = "sum(rate(istio_requests_total[5m])) by (source_app, destination_service_name)"
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "mTLS Policy Compliance"
            scorecard = {
              timeSeriesQuery = {
                prometheusQuery = "sum(istio_requests_total{security_policy=\"mutual_tls\"}) / sum(istio_requests_total)"
              }
              sparkChartView = {
                sparkChartType = "SPARK_BAR"
              }
              gaugeView = {
                lowerBound = 0.0
                upperBound = 1.0
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 4
          widget = {
            title = "Service Mesh Error Rates"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    prometheusQuery = "sum(rate(istio_requests_total{response_code!~\"2..\"}[5m])) by (destination_service_name)"
                  }
                  plotType = "STACKED_AREA"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Errors/sec"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_container_cluster.service_mesh_clusters]
}

# Create Cloud Logging sink for service mesh logs
resource "google_logging_project_sink" "service_mesh_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "service-mesh-logs-${local.name_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.log_bucket[0].name}"
  filter      = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"istio-system\""
  
  unique_writer_identity = true
  
  depends_on = [google_storage_bucket.log_bucket]
}

# Create Cloud Storage bucket for log storage
resource "google_storage_bucket" "log_bucket" {
  count = var.enable_logging ? 1 : 0
  
  name          = "service-mesh-logs-${var.project_id}-${local.name_suffix}"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = false
  }
  
  labels = local.common_labels
}

# Grant log writer permissions to the logging sink
resource "google_storage_bucket_iam_member" "log_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.log_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.service_mesh_logs[0].writer_identity
}