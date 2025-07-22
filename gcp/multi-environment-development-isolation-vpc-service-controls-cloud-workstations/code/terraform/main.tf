# Multi-Environment Development Isolation with VPC Service Controls and Cloud Workstations
# This Terraform configuration creates secure, isolated development environments using:
# - VPC Service Controls for security perimeters
# - Cloud Workstations for managed development environments
# - Cloud Filestore for shared storage
# - Identity-Aware Proxy for secure access

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  random_suffix = random_id.suffix.hex
  environments = {
    dev = {
      project_id = var.dev_project_id
      vpc_cidr   = var.dev_vpc_cidr
      name       = "development"
    }
    test = {
      project_id = var.test_project_id
      vpc_cidr   = var.test_vpc_cidr
      name       = "testing"
    }
    prod = {
      project_id = var.prod_project_id
      vpc_cidr   = var.prod_vpc_cidr
      name       = "production"
    }
  }
}

# Enable required APIs for all projects
resource "google_project_service" "apis" {
  for_each = {
    for pair in setproduct(keys(local.environments), var.services_to_enable) :
    "${pair[0]}-${replace(pair[1], ".", "-")}" => {
      project = local.environments[pair[0]].project_id
      service = pair[1]
    }
  }

  project = each.value.project
  service = each.value.service

  disable_on_destroy = false
}

# Create VPC networks for each environment
resource "google_compute_network" "vpc" {
  for_each = local.environments

  project                 = each.value.project_id
  name                    = "${each.key}-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.apis]
}

# Create subnets for each environment
resource "google_compute_subnetwork" "subnet" {
  for_each = local.environments

  project       = each.value.project_id
  name          = "${each.key}-subnet"
  ip_cidr_range = each.value.vpc_cidr
  region        = var.region
  network       = google_compute_network.vpc[each.key].id

  # Enable Private Google Access for security
  private_ip_google_access = true

  # Secondary IP ranges for GKE if needed in future
  secondary_ip_range {
    range_name    = "${each.key}-pods"
    ip_cidr_range = "172.16.${each.key == "dev" ? "0" : each.key == "test" ? "1" : "2"}.0/24"
  }

  secondary_ip_range {
    range_name    = "${each.key}-services"
    ip_cidr_range = "172.17.${each.key == "dev" ? "0" : each.key == "test" ? "1" : "2"}.0/24"
  }

  depends_on = [google_compute_network.vpc]
}

# Create firewall rules for each environment
resource "google_compute_firewall" "allow_internal" {
  for_each = local.environments

  project = each.value.project_id
  name    = "${each.key}-allow-internal"
  network = google_compute_network.vpc[each.key].name

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

  source_ranges = [each.value.vpc_cidr]
  target_tags   = ["${each.key}-internal"]
}

# Create firewall rules for SSH access through IAP
resource "google_compute_firewall" "allow_iap_ssh" {
  for_each = local.environments

  project = each.value.project_id
  name    = "${each.key}-allow-iap-ssh"
  network = google_compute_network.vpc[each.key].name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["${each.key}-workstation"]
}

# Create Cloud NAT for outbound internet access
resource "google_compute_router" "router" {
  for_each = local.environments

  project = each.value.project_id
  name    = "${each.key}-router"
  region  = var.region
  network = google_compute_network.vpc[each.key].id

  depends_on = [google_compute_subnetwork.subnet]
}

resource "google_compute_router_nat" "nat" {
  for_each = local.environments

  project                            = each.value.project_id
  name                               = "${each.key}-nat"
  router                             = google_compute_router.router[each.key].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Create Access Context Manager policy
resource "google_access_context_manager_access_policy" "policy" {
  parent = "organizations/${var.organization_id}"
  title  = var.access_policy_title

  depends_on = [google_project_service.apis]
}

# Create access level for internal users
resource "google_access_context_manager_access_level" "internal_users" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.policy.name}/accessLevels/internal_users"
  title  = "Internal Users Access Level"

  basic {
    conditions {
      members = var.internal_users
    }
  }
}

# Create VPC Service Controls perimeters for each environment
resource "google_access_context_manager_service_perimeter" "perimeter" {
  for_each = local.environments

  parent = "accessPolicies/${google_access_context_manager_access_policy.policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.policy.name}/servicePerimeters/${each.key}_perimeter"
  title  = "${title(each.value.name)} Environment Perimeter"

  status {
    restricted_services = var.restricted_services
    resources           = ["projects/${each.value.project_id}"]
    access_levels       = [google_access_context_manager_access_level.internal_users.name]
  }

  perimeter_type = "PERIMETER_TYPE_REGULAR"

  depends_on = [google_access_context_manager_access_level.internal_users]
}

# Create Cloud Filestore instances for shared storage
resource "google_filestore_instance" "filestore" {
  for_each = local.environments

  project  = each.value.project_id
  name     = "${each.key}-filestore"
  location = var.zone
  tier     = var.filestore_tier

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "${each.key}_share"
  }

  networks {
    network = google_compute_network.vpc[each.key].name
    modes   = ["MODE_IPV4"]
  }

  labels = merge(var.labels, {
    environment = each.key
  })

  depends_on = [
    google_compute_network.vpc,
    google_access_context_manager_service_perimeter.perimeter
  ]
}

# Create Cloud Source Repositories for version control
resource "google_sourcerepo_repository" "repo" {
  for_each = local.environments

  project = each.value.project_id
  name    = "${each.key}-repo"

  depends_on = [google_project_service.apis]
}

# Create Cloud Workstations clusters
resource "google_workstations_workstation_cluster" "cluster" {
  for_each = local.environments

  project               = each.value.project_id
  workstation_cluster_id = "${each.key}-cluster"
  location              = var.region

  network    = google_compute_network.vpc[each.key].id
  subnetwork = google_compute_subnetwork.subnet[each.key].id

  labels = merge(var.labels, {
    environment = each.key
  })

  depends_on = [
    google_compute_subnetwork.subnet,
    google_access_context_manager_service_perimeter.perimeter
  ]
}

# Create Cloud Workstations configurations
resource "google_workstations_workstation_config" "config" {
  for_each = local.environments

  project               = each.value.project_id
  workstation_config_id = "${each.key}-workstation-config"
  workstation_cluster_id = google_workstations_workstation_cluster.cluster[each.key].workstation_cluster_id
  location              = var.region

  host {
    gce_instance {
      machine_type     = var.workstation_machine_type
      boot_disk_size_gb = var.workstation_boot_disk_size_gb
      tags             = ["${each.key}-workstation"]
    }
  }

  container {
    image = var.workstation_image
    env = {
      FILESTORE_IP = google_filestore_instance.filestore[each.key].networks[0].ip_addresses[0]
    }
  }

  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb = var.workstation_persistent_disk_size_gb
      fs_type = "ext4"
    }
  }

  labels = merge(var.labels, {
    environment = each.key
  })

  depends_on = [
    google_workstations_workstation_cluster.cluster,
    google_filestore_instance.filestore
  ]
}

# Create sample workstations for demonstration
resource "google_workstations_workstation" "workstation" {
  for_each = local.environments

  project              = each.value.project_id
  workstation_id       = "${each.key}-workstation-1"
  workstation_config_id = google_workstations_workstation_config.config[each.key].workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.cluster[each.key].workstation_cluster_id
  location             = var.region

  labels = merge(var.labels, {
    environment = each.key
    workstation = "sample"
  })

  depends_on = [google_workstations_workstation_config.config]
}

# IAM bindings for IAP access to workstations
resource "google_project_iam_member" "iap_accessor" {
  for_each = {
    for pair in setproduct(keys(local.environments), var.internal_users) :
    "${pair[0]}-${replace(pair[1], "[@.]", "-")}" => {
      project = local.environments[pair[0]].project_id
      member  = pair[1]
    }
  }

  project = each.value.project
  role    = "roles/iap.httpsResourceAccessor"
  member  = each.value.member

  depends_on = [google_project_service.apis]
}

# IAM bindings for Cloud Workstations access
resource "google_project_iam_member" "workstation_user" {
  for_each = {
    for pair in setproduct(keys(local.environments), var.internal_users) :
    "${pair[0]}-${replace(pair[1], "[@.]", "-")}" => {
      project = local.environments[pair[0]].project_id
      member  = pair[1]
    }
  }

  project = each.value.project
  role    = "roles/workstations.user"
  member  = each.value.member

  depends_on = [google_project_service.apis]
}

# IAM bindings for Cloud Source Repositories access
resource "google_project_iam_member" "source_repo_admin" {
  for_each = {
    for pair in setproduct(keys(local.environments), var.internal_users) :
    "${pair[0]}-${replace(pair[1], "[@.]", "-")}" => {
      project = local.environments[pair[0]].project_id
      member  = pair[1]
    }
  }

  project = each.value.project
  role    = "roles/source.admin"
  member  = each.value.member

  depends_on = [google_project_service.apis]
}