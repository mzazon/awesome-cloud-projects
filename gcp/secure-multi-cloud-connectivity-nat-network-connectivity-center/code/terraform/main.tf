# Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center
# Terraform configuration for GCP multi-cloud networking architecture

# Data source for current project
data "google_project" "current" {}

# Data source for available zones in the region
data "google_compute_zones" "available" {
  region = var.region
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common tags for all resources
  common_labels = {
    environment = var.environment
    project     = "multi-cloud-connectivity"
    terraform   = "true"
    recipe      = "secure-multi-cloud-connectivity-nat-ncc"
  }
  
  # Resource names with random suffix
  hub_vpc_name    = "${var.hub_vpc_name}-${random_id.suffix.hex}"
  prod_vpc_name   = "${var.prod_vpc_name}-${random_id.suffix.hex}"
  dev_vpc_name    = "${var.dev_vpc_name}-${random_id.suffix.hex}"
  shared_vpc_name = "${var.shared_vpc_name}-${random_id.suffix.hex}"
}

#------------------------------------------------------------------------------
# VPC Networks and Subnets
#------------------------------------------------------------------------------

# Hub VPC Network for central connectivity
resource "google_compute_network" "hub_vpc" {
  name                    = local.hub_vpc_name
  description             = "Hub VPC for Network Connectivity Center"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  
  depends_on = [
    google_project_service.compute_api,
    google_project_service.networkconnectivity_api
  ]
}

# Hub subnet
resource "google_compute_subnetwork" "hub_subnet" {
  name          = "hub-subnet"
  network       = google_compute_network.hub_vpc.id
  ip_cidr_range = var.hub_subnet_cidr
  region        = var.region
  description   = "Hub subnet for central connectivity"
  
  # Enable private Google access for secure API communication
  private_ip_google_access = true
}

# Production VPC Network
resource "google_compute_network" "prod_vpc" {
  name                    = local.prod_vpc_name
  description             = "Production workloads VPC"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  
  depends_on = [
    google_project_service.compute_api
  ]
}

# Production subnet
resource "google_compute_subnetwork" "prod_subnet" {
  name          = "prod-subnet"
  network       = google_compute_network.prod_vpc.id
  ip_cidr_range = var.prod_subnet_cidr
  region        = var.region
  description   = "Production workloads subnet"
  
  private_ip_google_access = true
}

# Development VPC Network
resource "google_compute_network" "dev_vpc" {
  name                    = local.dev_vpc_name
  description             = "Development workloads VPC"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  
  depends_on = [
    google_project_service.compute_api
  ]
}

# Development subnet
resource "google_compute_subnetwork" "dev_subnet" {
  name          = "dev-subnet"
  network       = google_compute_network.dev_vpc.id
  ip_cidr_range = var.dev_subnet_cidr
  region        = var.region
  description   = "Development workloads subnet"
  
  private_ip_google_access = true
}

# Shared Services VPC Network
resource "google_compute_network" "shared_vpc" {
  name                    = local.shared_vpc_name
  description             = "Shared services VPC"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  
  depends_on = [
    google_project_service.compute_api
  ]
}

# Shared services subnet
resource "google_compute_subnetwork" "shared_subnet" {
  name          = "shared-subnet"
  network       = google_compute_network.shared_vpc.id
  ip_cidr_range = var.shared_subnet_cidr
  region        = var.region
  description   = "Shared services subnet"
  
  private_ip_google_access = true
}

#------------------------------------------------------------------------------
# Network Connectivity Center Hub and Spokes
#------------------------------------------------------------------------------

# Network Connectivity Center Hub
resource "google_network_connectivity_hub" "multi_cloud_hub" {
  name        = var.ncc_hub_name
  description = "Multi-cloud connectivity hub for enterprise workloads"
  labels      = local.common_labels
  
  depends_on = [
    google_project_service.networkconnectivity_api
  ]
}

# VPC Spoke for Production Network
resource "google_network_connectivity_spoke" "prod_spoke" {
  name        = "prod-spoke"
  hub         = google_network_connectivity_hub.multi_cloud_hub.id
  description = "Production VPC spoke"
  labels      = local.common_labels
  
  linked_vpc_network {
    uri = google_compute_network.prod_vpc.id
  }
  
  location = "global"
}

# VPC Spoke for Development Network
resource "google_network_connectivity_spoke" "dev_spoke" {
  name        = "dev-spoke"
  hub         = google_network_connectivity_hub.multi_cloud_hub.id
  description = "Development VPC spoke"
  labels      = local.common_labels
  
  linked_vpc_network {
    uri = google_compute_network.dev_vpc.id
  }
  
  location = "global"
}

# VPC Spoke for Shared Services Network
resource "google_network_connectivity_spoke" "shared_spoke" {
  name        = "shared-spoke"
  hub         = google_network_connectivity_hub.multi_cloud_hub.id
  description = "Shared services VPC spoke"
  labels      = local.common_labels
  
  linked_vpc_network {
    uri = google_compute_network.shared_vpc.id
  }
  
  location = "global"
}

#------------------------------------------------------------------------------
# Cloud Routers for BGP Management
#------------------------------------------------------------------------------

# Cloud Router in Hub VPC for BGP management
resource "google_compute_router" "hub_router" {
  name        = "hub-router"
  network     = google_compute_network.hub_vpc.id
  region      = var.region
  description = "BGP router for hybrid connectivity"
  
  # BGP ASN for the router
  bgp {
    asn = var.hub_bgp_asn
  }
}

# Cloud Router for Production VPC
resource "google_compute_router" "prod_router" {
  name        = "prod-router"
  network     = google_compute_network.prod_vpc.id
  region      = var.region
  description = "BGP router for production VPC"
  
  bgp {
    asn = var.prod_bgp_asn
  }
}

# Cloud Router for Development VPC
resource "google_compute_router" "dev_router" {
  name        = "dev-router"
  network     = google_compute_network.dev_vpc.id
  region      = var.region
  description = "BGP router for development VPC"
  
  bgp {
    asn = var.dev_bgp_asn
  }
}

# Cloud Router for Shared Services VPC
resource "google_compute_router" "shared_router" {
  name        = "shared-router"
  network     = google_compute_network.shared_vpc.id
  region      = var.region
  description = "BGP router for shared services VPC"
  
  bgp {
    asn = var.shared_bgp_asn
  }
}

#------------------------------------------------------------------------------
# HA VPN Gateway for Hybrid Connectivity
#------------------------------------------------------------------------------

# HA VPN Gateway in Hub VPC
resource "google_compute_ha_vpn_gateway" "hub_vpn_gateway" {
  name        = "hub-vpn-gateway"
  network     = google_compute_network.hub_vpc.id
  region      = var.region
  description = "HA VPN gateway for multi-cloud connectivity"
}

# External VPN Gateway (representing external cloud provider)
resource "google_compute_external_vpn_gateway" "external_cloud_gateway" {
  name            = "external-cloud-gateway"
  description     = "External cloud provider VPN gateway"
  redundancy_type = "SINGLE_IP_INTERNALLY_REDUNDANT"
  
  interface {
    id         = 0
    ip_address = var.external_cloud_vpn_ip
  }
}

# VPN Tunnel to External Cloud Provider
resource "google_compute_vpn_tunnel" "tunnel_to_external_cloud" {
  name          = "tunnel-to-external-cloud"
  region        = var.region
  description   = "VPN tunnel to external cloud provider"
  
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_vpn_gateway.id
  vpn_gateway_interface = 0
  
  peer_external_gateway           = google_compute_external_vpn_gateway.external_cloud_gateway.id
  peer_external_gateway_interface = 0
  
  shared_secret = var.vpn_shared_secret
  router        = google_compute_router.hub_router.id
  
  ike_version = 2
  
  depends_on = [
    google_compute_router.hub_router
  ]
}

# BGP Peer for External Cloud Provider
resource "google_compute_router_peer" "external_cloud_peer" {
  name      = "external-cloud-peer"
  router    = google_compute_router.hub_router.name
  region    = var.region
  interface = google_compute_router_interface.tunnel_interface.name
  
  peer_ip_address = var.external_cloud_bgp_peer_ip
  peer_asn        = var.external_cloud_bgp_asn
  
  depends_on = [
    google_compute_router_interface.tunnel_interface
  ]
}

# Router Interface for VPN Tunnel
resource "google_compute_router_interface" "tunnel_interface" {
  name       = "tunnel-interface"
  router     = google_compute_router.hub_router.name
  region     = var.region
  ip_range   = var.vpn_tunnel_ip_range
  vpn_tunnel = google_compute_vpn_tunnel.tunnel_to_external_cloud.name
}

# Hybrid Spoke for External Cloud Connectivity
resource "google_network_connectivity_spoke" "external_cloud_spoke" {
  name        = "external-cloud-spoke"
  hub         = google_network_connectivity_hub.multi_cloud_hub.id
  description = "Hybrid spoke for external cloud connectivity"
  labels      = local.common_labels
  
  linked_vpn_tunnels {
    uris                = [google_compute_vpn_tunnel.tunnel_to_external_cloud.id]
    site_to_site_data_transfer = var.enable_site_to_site_data_transfer
  }
  
  location = "global"
  
  depends_on = [
    google_compute_vpn_tunnel.tunnel_to_external_cloud
  ]
}

#------------------------------------------------------------------------------
# Cloud NAT Gateways for Secure Outbound Internet Access
#------------------------------------------------------------------------------

# Cloud NAT Gateway for Hub VPC
resource "google_compute_router_nat" "hub_nat_gateway" {
  name   = "hub-nat-gateway"
  router = google_compute_router.hub_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  # Enable logging for security monitoring
  log_config {
    enable = true
    filter = "ALL"
  }
  
  depends_on = [
    google_compute_router.hub_router
  ]
}

# Cloud NAT Gateway for Production VPC
resource "google_compute_router_nat" "prod_nat_gateway" {
  name   = "prod-nat-gateway"
  router = google_compute_router.prod_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ALL"
  }
  
  depends_on = [
    google_compute_router.prod_router
  ]
}

# Cloud NAT Gateway for Development VPC
resource "google_compute_router_nat" "dev_nat_gateway" {
  name   = "dev-nat-gateway"
  router = google_compute_router.dev_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ALL"
  }
  
  depends_on = [
    google_compute_router.dev_router
  ]
}

# Cloud NAT Gateway for Shared Services VPC
resource "google_compute_router_nat" "shared_nat_gateway" {
  name   = "shared-nat-gateway"
  router = google_compute_router.shared_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ALL"
  }
  
  depends_on = [
    google_compute_router.shared_router
  ]
}

#------------------------------------------------------------------------------
# Firewall Rules for Secure Communication
#------------------------------------------------------------------------------

# Firewall rules for Hub VPC (VPN and management traffic)
resource "google_compute_firewall" "hub_allow_vpn" {
  name        = "hub-allow-vpn"
  network     = google_compute_network.hub_vpc.name
  description = "Allow VPN and BGP traffic"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "179"]  # SSH and BGP
  }
  
  allow {
    protocol = "udp"
    ports    = ["500", "4500"]  # IKE and NAT-T
  }
  
  allow {
    protocol = "esp"
  }
  
  source_ranges = var.external_network_cidrs
  target_tags   = ["vpn-gateway"]
}

# Firewall rules for Production VPC
resource "google_compute_firewall" "prod_allow_internal" {
  name        = "prod-allow-internal"
  network     = google_compute_network.prod_vpc.name
  description = "Allow internal communication and management"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = concat([
    var.hub_subnet_cidr,
    var.dev_subnet_cidr,
    var.shared_subnet_cidr
  ], var.allowed_internal_cidrs)
  
  target_tags = ["production"]
}

# Firewall rules for Development VPC
resource "google_compute_firewall" "dev_allow_internal" {
  name        = "dev-allow-internal"
  network     = google_compute_network.dev_vpc.name
  description = "Allow internal communication and development traffic"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = concat([
    var.hub_subnet_cidr,
    var.prod_subnet_cidr,
    var.shared_subnet_cidr
  ], var.allowed_internal_cidrs)
  
  target_tags = ["development"]
}

# Firewall rules for Shared Services VPC
resource "google_compute_firewall" "shared_allow_internal" {
  name        = "shared-allow-internal"
  network     = google_compute_network.shared_vpc.name
  description = "Allow shared services access"
  
  allow {
    protocol = "tcp"
    ports    = ["22", "53", "80", "443"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = concat([
    var.hub_subnet_cidr,
    var.prod_subnet_cidr,
    var.dev_subnet_cidr
  ], var.allowed_internal_cidrs, var.external_network_cidrs)
  
  target_tags = ["shared-services"]
}

# Egress rules for Production VPC (internet access)
resource "google_compute_firewall" "prod_allow_egress" {
  name        = "prod-allow-egress"
  network     = google_compute_network.prod_vpc.name
  description = "Allow outbound internet access for production"
  direction   = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "53"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["production"]
}

# Egress rules for Development VPC (internet access)
resource "google_compute_firewall" "dev_allow_egress" {
  name        = "dev-allow-egress"
  network     = google_compute_network.dev_vpc.name
  description = "Allow outbound internet access for development"
  direction   = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "53", "8080"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["development"]
}

# Egress rules for Shared Services VPC (internet access)
resource "google_compute_firewall" "shared_allow_egress" {
  name        = "shared-allow-egress"
  network     = google_compute_network.shared_vpc.name
  description = "Allow outbound internet access for shared services"
  direction   = "EGRESS"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "53"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["shared-services"]
}

#------------------------------------------------------------------------------
# API Services
#------------------------------------------------------------------------------

# Enable Compute Engine API
resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Enable Network Connectivity API
resource "google_project_service" "networkconnectivity_api" {
  service            = "networkconnectivity.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Resource Manager API
resource "google_project_service" "cloudresourcemanager_api" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}