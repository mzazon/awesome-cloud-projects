# Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE
# This Terraform configuration creates a comprehensive fleet management solution
# with centralized cluster governance, automated backup policies, and GitOps configuration management

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct project IDs with random suffix if not provided
  fleet_host_project_id     = var.fleet_host_project_id != null ? var.fleet_host_project_id : "fleet-host-${random_id.suffix.hex}"
  workload_project_prod_id  = var.workload_project_prod_id != null ? var.workload_project_prod_id : "workload-prod-${random_id.suffix.hex}"
  workload_project_staging_id = var.workload_project_staging_id != null ? var.workload_project_staging_id : "workload-staging-${random_id.suffix.hex}"
  
  # Resource naming with prefix and suffix
  resource_suffix = var.resource_prefix != "" ? "${var.resource_prefix}-${random_id.suffix.hex}" : random_id.suffix.hex
  fleet_name     = "${var.fleet_name}-${random_id.suffix.hex}"
  
  # Cluster names for different environments
  prod_cluster_name    = "${var.cluster_name_prefix}-prod-${random_id.suffix.hex}"
  staging_cluster_name = "${var.cluster_name_prefix}-staging-${random_id.suffix.hex}"
  
  # Network names
  network_name = "${var.network_config.network_name}-${random_id.suffix.hex}"
  subnet_name  = "${var.network_config.subnet_name}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.common_labels, {
    fleet-name = local.fleet_name
    created-by = "terraform"
  })
}

# =============================================================================
# PROJECT CREATION AND CONFIGURATION
# =============================================================================

# Fleet Host Project - Central management project for the entire fleet
resource "google_project" "fleet_host" {
  count           = var.fleet_host_project_id == null ? 1 : 0
  project_id      = local.fleet_host_project_id
  name            = "Fleet Host Project"
  billing_account = var.billing_account
  org_id          = var.organization_id != "" ? var.organization_id : null
  
  labels = local.common_labels
}

# Production Workload Project
resource "google_project" "workload_prod" {
  count           = var.workload_project_prod_id == null ? 1 : 0
  project_id      = local.workload_project_prod_id
  name            = "Production Workload Project"
  billing_account = var.billing_account
  org_id          = var.organization_id != "" ? var.organization_id : null
  
  labels = merge(local.common_labels, {
    environment = "production"
  })
}

# Staging Workload Project
resource "google_project" "workload_staging" {
  count           = var.workload_project_staging_id == null ? 1 : 0
  project_id      = local.workload_project_staging_id
  name            = "Staging Workload Project"
  billing_account = var.billing_account
  org_id          = var.organization_id != "" ? var.organization_id : null
  
  labels = merge(local.common_labels, {
    environment = "staging"
  })
}

# Wait for project creation to complete
resource "time_sleep" "wait_for_projects" {
  count           = var.fleet_host_project_id == null ? 1 : 0
  depends_on      = [google_project.fleet_host, google_project.workload_prod, google_project.workload_staging]
  create_duration = "30s"
}

# =============================================================================
# API ENABLEMENT
# =============================================================================

# Enable APIs for Fleet Host Project
resource "google_project_service" "fleet_host_apis" {
  for_each = toset([
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "gkebackup.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "krmapihosting.googleapis.com",
    "anthosconfigmanagement.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = local.fleet_host_project_id
  service = each.value
  
  disable_on_destroy = false
  
  depends_on = [time_sleep.wait_for_projects]
}

# Enable APIs for Production Workload Project
resource "google_project_service" "workload_prod_apis" {
  for_each = toset([
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "gkebackup.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = local.workload_project_prod_id
  service = each.value
  
  disable_on_destroy = false
  
  depends_on = [time_sleep.wait_for_projects]
}

# Enable APIs for Staging Workload Project
resource "google_project_service" "workload_staging_apis" {
  for_each = toset([
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "gkebackup.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = local.workload_project_staging_id
  service = each.value
  
  disable_on_destroy = false
  
  depends_on = [time_sleep.wait_for_projects]
}

# =============================================================================
# NETWORKING INFRASTRUCTURE
# =============================================================================

# VPC Network for Production Environment
resource "google_compute_network" "prod_network" {
  count                   = var.network_config.create_vpc_network ? 1 : 0
  project                 = local.workload_project_prod_id
  name                    = "${local.network_name}-prod"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.workload_prod_apis]
}

# Subnet for Production GKE Cluster
resource "google_compute_subnetwork" "prod_subnet" {
  count         = var.network_config.create_vpc_network ? 1 : 0
  project       = local.workload_project_prod_id
  name          = "${local.subnet_name}-prod"
  ip_cidr_range = var.network_config.subnet_cidr
  region        = var.region
  network       = google_compute_network.prod_network[0].id
  
  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.network_config.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.network_config.services_cidr
  }
  
  private_ip_google_access = true
}

# VPC Network for Staging Environment
resource "google_compute_network" "staging_network" {
  count                   = var.network_config.create_vpc_network ? 1 : 0
  project                 = local.workload_project_staging_id
  name                    = "${local.network_name}-staging"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.workload_staging_apis]
}

# Subnet for Staging GKE Cluster
resource "google_compute_subnetwork" "staging_subnet" {
  count         = var.network_config.create_vpc_network ? 1 : 0
  project       = local.workload_project_staging_id
  name          = "${local.subnet_name}-staging"
  ip_cidr_range = "10.10.0.0/24"  # Different CIDR for staging
  region        = var.region
  network       = google_compute_network.staging_network[0].id
  
  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.11.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.12.0.0/16"
  }
  
  private_ip_google_access = true
}

# =============================================================================
# IAM SERVICE ACCOUNTS AND PERMISSIONS
# =============================================================================

# Fleet Manager Service Account
resource "google_service_account" "fleet_manager" {
  project      = local.fleet_host_project_id
  account_id   = "fleet-manager-${random_id.suffix.hex}"
  display_name = "Fleet Manager Service Account"
  description  = "Service account for managing fleet operations across projects"
  
  depends_on = [google_project_service.fleet_host_apis]
}

# Config Connector Service Account for Production
resource "google_service_account" "config_connector_prod" {
  count        = var.enable_config_connector ? 1 : 0
  project      = local.workload_project_prod_id
  account_id   = "cnrm-system-${random_id.suffix.hex}"
  display_name = "Config Connector Service Account - Production"
  description  = "Service account for Config Connector GitOps operations"
  
  depends_on = [google_project_service.workload_prod_apis]
}

# Config Connector Service Account for Staging
resource "google_service_account" "config_connector_staging" {
  count        = var.enable_config_connector ? 1 : 0
  project      = local.workload_project_staging_id
  account_id   = "cnrm-system-${random_id.suffix.hex}"
  display_name = "Config Connector Service Account - Staging"
  description  = "Service account for Config Connector GitOps operations"
  
  depends_on = [google_project_service.workload_staging_apis]
}

# IAM bindings for Fleet Manager
resource "google_project_iam_member" "fleet_manager_permissions" {
  for_each = toset([
    "roles/container.clusterViewer",
    "roles/gkehub.viewer",
    "roles/gkebackup.admin"
  ])
  
  project = local.workload_project_prod_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.fleet_manager.email}"
}

resource "google_project_iam_member" "fleet_manager_permissions_staging" {
  for_each = toset([
    "roles/container.clusterViewer",
    "roles/gkehub.viewer", 
    "roles/gkebackup.admin"
  ])
  
  project = local.workload_project_staging_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.fleet_manager.email}"
}

# IAM bindings for Config Connector - Production
resource "google_project_iam_member" "config_connector_prod_permissions" {
  count   = var.enable_config_connector ? 1 : 0
  project = local.workload_project_prod_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.config_connector_prod[0].email}"
}

# IAM bindings for Config Connector - Staging
resource "google_project_iam_member" "config_connector_staging_permissions" {
  count   = var.enable_config_connector ? 1 : 0
  project = local.workload_project_staging_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.config_connector_staging[0].email}"
}

# =============================================================================
# GKE CLUSTERS
# =============================================================================

# Production GKE Cluster
resource "google_container_cluster" "prod_cluster" {
  project  = local.workload_project_prod_id
  name     = local.prod_cluster_name
  location = var.region
  
  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Networking configuration
  network    = var.network_config.create_vpc_network ? google_compute_network.prod_network[0].id : "default"
  subnetwork = var.network_config.create_vpc_network ? google_compute_subnetwork.prod_subnet[0].id : null
  
  # IP allocation policy for alias IPs
  ip_allocation_policy {
    cluster_secondary_range_name  = var.network_config.create_vpc_network ? "pods" : null
    services_secondary_range_name = var.network_config.create_vpc_network ? "services" : null
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.security_config.enable_private_endpoint
    enable_private_endpoint = var.security_config.enable_private_endpoint
    master_ipv4_cidr_block  = var.network_config.master_cidr
  }
  
  # Workload Identity configuration
  workload_identity_config {
    workload_pool = var.security_config.enable_workload_identity ? "${local.workload_project_prod_id}.svc.id.goog" : null
  }
  
  # Network policy configuration
  network_policy {
    enabled  = var.security_config.enable_network_policy
    provider = var.security_config.enable_network_policy ? "CALICO" : null
  }
  
  # Addons configuration
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = !var.security_config.enable_network_policy
    }
    config_connector_config {
      enabled = var.enable_config_connector
    }
    gke_backup_agent_config {
      enabled = var.enable_backup
    }
  }
  
  # Cluster security configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  # Binary authorization configuration
  enable_binary_authorization = var.security_config.enable_binary_authorization
  
  # Logging and monitoring
  logging_service    = var.enable_monitoring ? "logging.googleapis.com/kubernetes" : null
  monitoring_service = var.enable_monitoring ? "monitoring.googleapis.com/kubernetes" : null
  
  resource_labels = local.common_labels
  
  depends_on = [
    google_project_service.workload_prod_apis,
    google_compute_subnetwork.prod_subnet
  ]
}

# Production Node Pool
resource "google_container_node_pool" "prod_node_pool" {
  project    = local.workload_project_prod_id
  name       = "${local.prod_cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.prod_cluster.name
  
  initial_node_count = var.prod_cluster_config.initial_node_count
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.prod_cluster_config.min_node_count
    max_node_count = var.prod_cluster_config.max_node_count
  }
  
  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.prod_cluster_config.machine_type
    disk_size_gb = var.prod_cluster_config.disk_size_gb
    disk_type    = var.prod_cluster_config.disk_type
    
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.fleet_manager.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Workload Identity configuration
    workload_metadata_config {
      mode = var.security_config.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
    
    # Shielded Instance configuration
    shielded_instance_config {
      enable_secure_boot          = var.security_config.enable_shielded_nodes
      enable_integrity_monitoring = var.security_config.enable_shielded_nodes
    }
    
    labels = merge(local.common_labels, {
      environment = "production"
    })
    
    tags = ["gke-node", "production"]
  }
  
  # Node management
  management {
    auto_repair  = var.prod_cluster_config.enable_autorepair
    auto_upgrade = var.prod_cluster_config.enable_autoupgrade
  }
  
  # Upgrade settings
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }
}

# Staging GKE Cluster
resource "google_container_cluster" "staging_cluster" {
  project  = local.workload_project_staging_id
  name     = local.staging_cluster_name
  location = var.region
  
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Networking configuration
  network    = var.network_config.create_vpc_network ? google_compute_network.staging_network[0].id : "default"
  subnetwork = var.network_config.create_vpc_network ? google_compute_subnetwork.staging_subnet[0].id : null
  
  # IP allocation policy for alias IPs
  ip_allocation_policy {
    cluster_secondary_range_name  = var.network_config.create_vpc_network ? "pods" : null
    services_secondary_range_name = var.network_config.create_vpc_network ? "services" : null
  }
  
  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.security_config.enable_private_endpoint
    enable_private_endpoint = var.security_config.enable_private_endpoint
    master_ipv4_cidr_block  = "172.17.0.0/28"  # Different CIDR for staging
  }
  
  # Workload Identity configuration
  workload_identity_config {
    workload_pool = var.security_config.enable_workload_identity ? "${local.workload_project_staging_id}.svc.id.goog" : null
  }
  
  # Network policy configuration
  network_policy {
    enabled  = var.security_config.enable_network_policy
    provider = var.security_config.enable_network_policy ? "CALICO" : null
  }
  
  # Addons configuration
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = !var.security_config.enable_network_policy
    }
    config_connector_config {
      enabled = var.enable_config_connector
    }
    gke_backup_agent_config {
      enabled = var.enable_backup
    }
  }
  
  # Cluster security configuration
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  # Binary authorization configuration
  enable_binary_authorization = var.security_config.enable_binary_authorization
  
  # Logging and monitoring
  logging_service    = var.enable_monitoring ? "logging.googleapis.com/kubernetes" : null
  monitoring_service = var.enable_monitoring ? "monitoring.googleapis.com/kubernetes" : null
  
  resource_labels = merge(local.common_labels, {
    environment = "staging"
  })
  
  depends_on = [
    google_project_service.workload_staging_apis,
    google_compute_subnetwork.staging_subnet
  ]
}

# Staging Node Pool
resource "google_container_node_pool" "staging_node_pool" {
  project    = local.workload_project_staging_id
  name       = "${local.staging_cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.staging_cluster.name
  
  initial_node_count = var.staging_cluster_config.initial_node_count
  
  # Autoscaling configuration
  autoscaling {
    min_node_count = var.staging_cluster_config.min_node_count
    max_node_count = var.staging_cluster_config.max_node_count
  }
  
  # Node configuration
  node_config {
    preemptible  = false
    machine_type = var.staging_cluster_config.machine_type
    disk_size_gb = var.staging_cluster_config.disk_size_gb
    disk_type    = var.staging_cluster_config.disk_type
    
    service_account = google_service_account.fleet_manager.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Workload Identity configuration
    workload_metadata_config {
      mode = var.security_config.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }
    
    # Shielded Instance configuration
    shielded_instance_config {
      enable_secure_boot          = var.security_config.enable_shielded_nodes
      enable_integrity_monitoring = var.security_config.enable_shielded_nodes
    }
    
    labels = merge(local.common_labels, {
      environment = "staging"
    })
    
    tags = ["gke-node", "staging"]
  }
  
  # Node management
  management {
    auto_repair  = var.staging_cluster_config.enable_autorepair
    auto_upgrade = var.staging_cluster_config.enable_autoupgrade
  }
  
  # Upgrade settings
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }
}

# =============================================================================
# FLEET REGISTRATION
# =============================================================================

# Register Production Cluster to Fleet
resource "google_gke_hub_membership" "prod_membership" {
  provider      = google-beta
  project       = local.fleet_host_project_id
  membership_id = local.prod_cluster_name
  
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.prod_cluster.id}"
    }
  }
  
  labels = merge(local.common_labels, {
    environment = "production"
    cluster     = local.prod_cluster_name
  })
  
  depends_on = [
    google_project_service.fleet_host_apis,
    google_container_cluster.prod_cluster
  ]
}

# Register Staging Cluster to Fleet
resource "google_gke_hub_membership" "staging_membership" {
  provider      = google-beta
  project       = local.fleet_host_project_id
  membership_id = local.staging_cluster_name
  
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.staging_cluster.id}"
    }
  }
  
  labels = merge(local.common_labels, {
    environment = "staging"
    cluster     = local.staging_cluster_name
  })
  
  depends_on = [
    google_project_service.fleet_host_apis,
    google_container_cluster.staging_cluster
  ]
}

# =============================================================================
# CONFIG MANAGEMENT FEATURE
# =============================================================================

# Enable Config Management Feature for the Fleet
resource "google_gke_hub_feature" "config_management" {
  provider = google-beta
  project  = local.fleet_host_project_id
  name     = "configmanagement"
  location = "global"
  
  depends_on = [
    google_project_service.fleet_host_apis,
    google_gke_hub_membership.prod_membership,
    google_gke_hub_membership.staging_membership
  ]
}

# Configure Config Management for Production Cluster
resource "google_gke_hub_feature_membership" "prod_config_management" {
  provider   = google-beta
  project    = local.fleet_host_project_id
  location   = "global"
  feature    = google_gke_hub_feature.config_management.name
  membership = google_gke_hub_membership.prod_membership.membership_id
  
  configmanagement {
    config_sync {
      source_format = "unstructured"
      enabled       = var.config_management.enable_config_sync
    }
    
    policy_controller {
      enabled                    = var.config_management.enable_policy_controller
      referential_rules_enabled  = var.config_management.referential_rules_enabled
      log_denies_enabled         = var.config_management.log_denies_enabled
      mutation_enabled           = var.config_management.mutation_enabled
    }
    
    hierarchy_controller {
      enabled                = true
      enable_hierarchical_resource_quota = true
      enable_pod_tree_labels = true
    }
  }
}

# Configure Config Management for Staging Cluster
resource "google_gke_hub_feature_membership" "staging_config_management" {
  provider   = google-beta
  project    = local.fleet_host_project_id
  location   = "global"
  feature    = google_gke_hub_feature.config_management.name
  membership = google_gke_hub_membership.staging_membership.membership_id
  
  configmanagement {
    config_sync {
      source_format = "unstructured"
      enabled       = var.config_management.enable_config_sync
    }
    
    policy_controller {
      enabled                    = var.config_management.enable_policy_controller
      referential_rules_enabled  = var.config_management.referential_rules_enabled
      log_denies_enabled         = var.config_management.log_denies_enabled
      mutation_enabled           = var.config_management.mutation_enabled
    }
    
    hierarchy_controller {
      enabled                = true
      enable_hierarchical_resource_quota = true
      enable_pod_tree_labels = true
    }
  }
}

# =============================================================================
# BACKUP FOR GKE
# =============================================================================

# Backup Plan for Production Cluster
resource "google_gke_backup_backup_plan" "prod_backup_plan" {
  count    = var.enable_backup ? 1 : 0
  project  = local.fleet_host_project_id
  name     = "fleet-backup-plan-prod-${random_id.suffix.hex}"
  cluster  = google_container_cluster.prod_cluster.id
  location = var.region
  
  description = "Daily backup plan for production workloads"
  
  backup_schedule {
    cron_schedule = var.backup_plan_config.prod_schedule
  }
  
  backup_config {
    include_volume_data = var.backup_plan_config.include_volume_data
    include_secrets     = var.backup_plan_config.include_secrets
    all_namespaces      = true
  }
  
  retention_policy {
    backup_delete_lock_days = var.backup_plan_config.prod_retention_days
    backup_retain_days      = var.backup_plan_config.prod_retention_days
  }
  
  labels = merge(local.common_labels, {
    environment = "production"
    backup-type = "automated"
  })
  
  depends_on = [
    google_project_service.fleet_host_apis,
    google_container_cluster.prod_cluster
  ]
}

# Backup Plan for Staging Cluster
resource "google_gke_backup_backup_plan" "staging_backup_plan" {
  count    = var.enable_backup ? 1 : 0
  project  = local.fleet_host_project_id
  name     = "fleet-backup-plan-staging-${random_id.suffix.hex}"
  cluster  = google_container_cluster.staging_cluster.id
  location = var.region
  
  description = "Weekly backup plan for staging workloads"
  
  backup_schedule {
    cron_schedule = var.backup_plan_config.staging_schedule
  }
  
  backup_config {
    include_volume_data = var.backup_plan_config.include_volume_data
    include_secrets     = var.backup_plan_config.include_secrets
    all_namespaces      = true
  }
  
  retention_policy {
    backup_delete_lock_days = var.backup_plan_config.staging_retention_days
    backup_retain_days      = var.backup_plan_config.staging_retention_days
  }
  
  labels = merge(local.common_labels, {
    environment = "staging"
    backup-type = "automated"
  })
  
  depends_on = [
    google_project_service.fleet_host_apis,
    google_container_cluster.staging_cluster
  ]
}