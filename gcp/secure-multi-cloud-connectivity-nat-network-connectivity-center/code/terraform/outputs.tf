# Outputs for Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center
# Terraform outputs for GCP multi-cloud networking architecture

#------------------------------------------------------------------------------
# Network Connectivity Center Outputs
#------------------------------------------------------------------------------

output "ncc_hub_id" {
  description = "ID of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.multi_cloud_hub.id
}

output "ncc_hub_name" {
  description = "Name of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.multi_cloud_hub.name
}

output "ncc_hub_uri" {
  description = "URI of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.multi_cloud_hub.uri
}

output "ncc_hub_state" {
  description = "State of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.multi_cloud_hub.state
}

#------------------------------------------------------------------------------
# VPC Network Outputs
#------------------------------------------------------------------------------

output "vpc_networks" {
  description = "Information about all VPC networks created"
  value = {
    hub_vpc = {
      id            = google_compute_network.hub_vpc.id
      name          = google_compute_network.hub_vpc.name
      self_link     = google_compute_network.hub_vpc.self_link
      gateway_ipv4  = google_compute_network.hub_vpc.gateway_ipv4
    }
    prod_vpc = {
      id            = google_compute_network.prod_vpc.id
      name          = google_compute_network.prod_vpc.name
      self_link     = google_compute_network.prod_vpc.self_link
      gateway_ipv4  = google_compute_network.prod_vpc.gateway_ipv4
    }
    dev_vpc = {
      id            = google_compute_network.dev_vpc.id
      name          = google_compute_network.dev_vpc.name
      self_link     = google_compute_network.dev_vpc.self_link
      gateway_ipv4  = google_compute_network.dev_vpc.gateway_ipv4
    }
    shared_vpc = {
      id            = google_compute_network.shared_vpc.id
      name          = google_compute_network.shared_vpc.name
      self_link     = google_compute_network.shared_vpc.self_link
      gateway_ipv4  = google_compute_network.shared_vpc.gateway_ipv4
    }
  }
}

output "subnet_information" {
  description = "Information about all subnets created"
  value = {
    hub_subnet = {
      id                   = google_compute_subnetwork.hub_subnet.id
      name                 = google_compute_subnetwork.hub_subnet.name
      ip_cidr_range        = google_compute_subnetwork.hub_subnet.ip_cidr_range
      gateway_address      = google_compute_subnetwork.hub_subnet.gateway_address
      self_link           = google_compute_subnetwork.hub_subnet.self_link
    }
    prod_subnet = {
      id                   = google_compute_subnetwork.prod_subnet.id
      name                 = google_compute_subnetwork.prod_subnet.name
      ip_cidr_range        = google_compute_subnetwork.prod_subnet.ip_cidr_range
      gateway_address      = google_compute_subnetwork.prod_subnet.gateway_address
      self_link           = google_compute_subnetwork.prod_subnet.self_link
    }
    dev_subnet = {
      id                   = google_compute_subnetwork.dev_subnet.id
      name                 = google_compute_subnetwork.dev_subnet.name
      ip_cidr_range        = google_compute_subnetwork.dev_subnet.ip_cidr_range
      gateway_address      = google_compute_subnetwork.dev_subnet.gateway_address
      self_link           = google_compute_subnetwork.dev_subnet.self_link
    }
    shared_subnet = {
      id                   = google_compute_subnetwork.shared_subnet.id
      name                 = google_compute_subnetwork.shared_subnet.name
      ip_cidr_range        = google_compute_subnetwork.shared_subnet.ip_cidr_range
      gateway_address      = google_compute_subnetwork.shared_subnet.gateway_address
      self_link           = google_compute_subnetwork.shared_subnet.self_link
    }
  }
}

#------------------------------------------------------------------------------
# Network Connectivity Center Spoke Outputs
#------------------------------------------------------------------------------

output "ncc_spokes" {
  description = "Information about Network Connectivity Center spokes"
  value = {
    prod_spoke = {
      id    = google_network_connectivity_spoke.prod_spoke.id
      name  = google_network_connectivity_spoke.prod_spoke.name
      uri   = google_network_connectivity_spoke.prod_spoke.uri
      state = google_network_connectivity_spoke.prod_spoke.state
    }
    dev_spoke = {
      id    = google_network_connectivity_spoke.dev_spoke.id
      name  = google_network_connectivity_spoke.dev_spoke.name
      uri   = google_network_connectivity_spoke.dev_spoke.uri
      state = google_network_connectivity_spoke.dev_spoke.state
    }
    shared_spoke = {
      id    = google_network_connectivity_spoke.shared_spoke.id
      name  = google_network_connectivity_spoke.shared_spoke.name
      uri   = google_network_connectivity_spoke.shared_spoke.uri
      state = google_network_connectivity_spoke.shared_spoke.state
    }
    external_cloud_spoke = {
      id    = google_network_connectivity_spoke.external_cloud_spoke.id
      name  = google_network_connectivity_spoke.external_cloud_spoke.name
      uri   = google_network_connectivity_spoke.external_cloud_spoke.uri
      state = google_network_connectivity_spoke.external_cloud_spoke.state
    }
  }
}

#------------------------------------------------------------------------------
# VPN Gateway Outputs
#------------------------------------------------------------------------------

output "vpn_gateway_information" {
  description = "Information about the HA VPN gateway"
  value = {
    id         = google_compute_ha_vpn_gateway.hub_vpn_gateway.id
    name       = google_compute_ha_vpn_gateway.hub_vpn_gateway.name
    self_link  = google_compute_ha_vpn_gateway.hub_vpn_gateway.self_link
    interfaces = [
      for interface in google_compute_ha_vpn_gateway.hub_vpn_gateway.vpn_interfaces : {
        id         = interface.id
        ip_address = interface.ip_address
      }
    ]
  }
}

output "vpn_tunnel_information" {
  description = "Information about VPN tunnels"
  value = {
    external_cloud_tunnel = {
      id            = google_compute_vpn_tunnel.tunnel_to_external_cloud.id
      name          = google_compute_vpn_tunnel.tunnel_to_external_cloud.name
      self_link     = google_compute_vpn_tunnel.tunnel_to_external_cloud.self_link
      detailed_status = google_compute_vpn_tunnel.tunnel_to_external_cloud.detailed_status
    }
  }
}

output "external_vpn_gateway_information" {
  description = "Information about the external VPN gateway"
  value = {
    id        = google_compute_external_vpn_gateway.external_cloud_gateway.id
    name      = google_compute_external_vpn_gateway.external_cloud_gateway.name
    self_link = google_compute_external_vpn_gateway.external_cloud_gateway.self_link
  }
}

#------------------------------------------------------------------------------
# Cloud Router Outputs
#------------------------------------------------------------------------------

output "cloud_routers" {
  description = "Information about all Cloud Routers"
  value = {
    hub_router = {
      id        = google_compute_router.hub_router.id
      name      = google_compute_router.hub_router.name
      self_link = google_compute_router.hub_router.self_link
      bgp_asn   = google_compute_router.hub_router.bgp[0].asn
    }
    prod_router = {
      id        = google_compute_router.prod_router.id
      name      = google_compute_router.prod_router.name
      self_link = google_compute_router.prod_router.self_link
      bgp_asn   = google_compute_router.prod_router.bgp[0].asn
    }
    dev_router = {
      id        = google_compute_router.dev_router.id
      name      = google_compute_router.dev_router.name
      self_link = google_compute_router.dev_router.self_link
      bgp_asn   = google_compute_router.dev_router.bgp[0].asn
    }
    shared_router = {
      id        = google_compute_router.shared_router.id
      name      = google_compute_router.shared_router.name
      self_link = google_compute_router.shared_router.self_link
      bgp_asn   = google_compute_router.shared_router.bgp[0].asn
    }
  }
}

output "bgp_peer_information" {
  description = "Information about BGP peers"
  value = {
    external_cloud_peer = {
      name            = google_compute_router_peer.external_cloud_peer.name
      peer_ip_address = google_compute_router_peer.external_cloud_peer.peer_ip_address
      peer_asn        = google_compute_router_peer.external_cloud_peer.peer_asn
    }
  }
}

#------------------------------------------------------------------------------
# Cloud NAT Gateway Outputs
#------------------------------------------------------------------------------

output "nat_gateways" {
  description = "Information about Cloud NAT gateways"
  value = {
    hub_nat = {
      name      = google_compute_router_nat.hub_nat_gateway.name
      router    = google_compute_router_nat.hub_nat_gateway.router
      region    = google_compute_router_nat.hub_nat_gateway.region
    }
    prod_nat = {
      name      = google_compute_router_nat.prod_nat_gateway.name
      router    = google_compute_router_nat.prod_nat_gateway.router
      region    = google_compute_router_nat.prod_nat_gateway.region
    }
    dev_nat = {
      name      = google_compute_router_nat.dev_nat_gateway.name
      router    = google_compute_router_nat.dev_nat_gateway.router
      region    = google_compute_router_nat.dev_nat_gateway.region
    }
    shared_nat = {
      name      = google_compute_router_nat.shared_nat_gateway.name
      router    = google_compute_router_nat.shared_nat_gateway.router
      region    = google_compute_router_nat.shared_nat_gateway.region
    }
  }
}

#------------------------------------------------------------------------------
# Firewall Rules Outputs
#------------------------------------------------------------------------------

output "firewall_rules" {
  description = "Information about firewall rules created"
  value = {
    hub_vpn_firewall = {
      name      = google_compute_firewall.hub_allow_vpn.name
      network   = google_compute_firewall.hub_allow_vpn.network
      direction = google_compute_firewall.hub_allow_vpn.direction
    }
    prod_internal_firewall = {
      name      = google_compute_firewall.prod_allow_internal.name
      network   = google_compute_firewall.prod_allow_internal.network
      direction = google_compute_firewall.prod_allow_internal.direction
    }
    dev_internal_firewall = {
      name      = google_compute_firewall.dev_allow_internal.name
      network   = google_compute_firewall.dev_allow_internal.network
      direction = google_compute_firewall.dev_allow_internal.direction
    }
    shared_internal_firewall = {
      name      = google_compute_firewall.shared_allow_internal.name
      network   = google_compute_firewall.shared_allow_internal.network
      direction = google_compute_firewall.shared_allow_internal.direction
    }
    prod_egress_firewall = {
      name      = google_compute_firewall.prod_allow_egress.name
      network   = google_compute_firewall.prod_allow_egress.network
      direction = google_compute_firewall.prod_allow_egress.direction
    }
    dev_egress_firewall = {
      name      = google_compute_firewall.dev_allow_egress.name
      network   = google_compute_firewall.dev_allow_egress.network
      direction = google_compute_firewall.dev_allow_egress.direction
    }
    shared_egress_firewall = {
      name      = google_compute_firewall.shared_allow_egress.name
      network   = google_compute_firewall.shared_allow_egress.network
      direction = google_compute_firewall.shared_allow_egress.direction
    }
  }
}

#------------------------------------------------------------------------------
# Connectivity Summary Outputs
#------------------------------------------------------------------------------

output "connectivity_summary" {
  description = "Summary of multi-cloud connectivity configuration"
  value = {
    hub_name                    = google_network_connectivity_hub.multi_cloud_hub.name
    total_vpc_networks          = 4
    total_spokes               = 4
    vpn_gateway_external_ips   = [
      for interface in google_compute_ha_vpn_gateway.hub_vpn_gateway.vpn_interfaces : interface.ip_address
    ]
    external_cloud_connectivity = true
    nat_enabled_networks       = [
      google_compute_network.hub_vpc.name,
      google_compute_network.prod_vpc.name,
      google_compute_network.dev_vpc.name,
      google_compute_network.shared_vpc.name
    ]
  }
}

#------------------------------------------------------------------------------
# Configuration Instructions Outputs
#------------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps for completing the multi-cloud connectivity setup"
  value = {
    vpn_configuration = "Configure your external cloud provider's VPN gateway with the following IPs: ${join(", ", [for interface in google_compute_ha_vpn_gateway.hub_vpn_gateway.vpn_interfaces : interface.ip_address])}"
    bgp_configuration = "Set up BGP peering with ASN ${var.external_cloud_bgp_asn} and peer IP ${var.external_cloud_bgp_peer_ip}"
    firewall_rules    = "Review and adjust firewall rules based on your specific security requirements"
    monitoring        = "Set up monitoring for VPN tunnel status and BGP session health"
  }
}

#------------------------------------------------------------------------------
# Resource Naming Information
#------------------------------------------------------------------------------

output "resource_naming" {
  description = "Information about resource naming convention used"
  value = {
    random_suffix = random_id.suffix.hex
    hub_vpc_name  = local.hub_vpc_name
    prod_vpc_name = local.prod_vpc_name
    dev_vpc_name  = local.dev_vpc_name
    shared_vpc_name = local.shared_vpc_name
  }
}