# ==============================================================================
# Service Discovery with Traffic Director and Cloud DNS - Outputs
# ==============================================================================

# Project Information
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The deployment region"
  value       = var.region
}

output "zones" {
  description = "The zones where instances are deployed"
  value       = local.zones
}

# Network Information
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.service_mesh_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.service_mesh_vpc.id
}

output "subnet_name" {
  description = "Name of the service mesh subnet"
  value       = google_compute_subnetwork.service_mesh_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the service mesh subnet"
  value       = google_compute_subnetwork.service_mesh_subnet.ip_cidr_range
}

# Service Discovery Information
output "service_name" {
  description = "The generated service name with random suffix"
  value       = local.service_name
}

output "domain_name" {
  description = "The fully qualified domain name for the service"
  value       = local.domain_name
}

output "service_vip" {
  description = "The virtual IP address for the service"
  value       = google_compute_global_forwarding_rule.service_forwarding_rule.ip_address
}

# DNS Configuration
output "private_dns_zone_name" {
  description = "Name of the private DNS zone"
  value       = google_dns_managed_zone.private_zone.name
}

output "private_dns_zone_dns_name" {
  description = "DNS name of the private zone"
  value       = google_dns_managed_zone.private_zone.dns_name
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = google_dns_managed_zone.private_zone.id
}

output "public_dns_zone_name" {
  description = "Name of the public DNS zone (if created)"
  value       = var.create_public_dns ? google_dns_managed_zone.public_zone[0].name : null
}

output "public_dns_zone_dns_name" {
  description = "DNS name of the public zone (if created)"
  value       = var.create_public_dns ? google_dns_managed_zone.public_zone[0].dns_name : null
}

output "public_dns_zone_id" {
  description = "ID of the public DNS zone (if created)"
  value       = var.create_public_dns ? google_dns_managed_zone.public_zone[0].id : null
}

output "public_dns_name_servers" {
  description = "Name servers for the public DNS zone (if created)"
  value       = var.create_public_dns ? google_dns_managed_zone.public_zone[0].name_servers : null
}

# Service Instance Information
output "service_instances" {
  description = "Information about deployed service instances"
  value = {
    for instance_key, instance in google_compute_instance_from_template.service_instances : 
    instance_key => {
      name               = instance.name
      zone               = instance.zone
      internal_ip        = instance.network_interface[0].network_ip
      external_ip        = var.assign_external_ip ? (length(instance.network_interface[0].access_config) > 0 ? instance.network_interface[0].access_config[0].nat_ip : null) : null
      machine_type       = instance.machine_type
      self_link          = instance.self_link
    }
  }
}

output "instance_template_name" {
  description = "Name of the instance template"
  value       = google_compute_instance_template.service_template.name
}

# Network Endpoint Groups
output "network_endpoint_groups" {
  description = "Information about Network Endpoint Groups"
  value = {
    for neg_key, neg in google_compute_network_endpoint_group.service_negs :
    neg_key => {
      name        = neg.name
      zone        = neg.zone
      id          = neg.id
      self_link   = neg.self_link
      size        = neg.size
    }
  }
}

# Traffic Director Configuration
output "backend_service_name" {
  description = "Name of the Traffic Director backend service"
  value       = google_compute_backend_service.service_backend.name
}

output "backend_service_id" {
  description = "ID of the Traffic Director backend service"
  value       = google_compute_backend_service.service_backend.id
}

output "url_map_name" {
  description = "Name of the URL map"
  value       = google_compute_url_map.service_url_map.name
}

output "url_map_id" {
  description = "ID of the URL map"
  value       = google_compute_url_map.service_url_map.id
}

output "target_proxy_name" {
  description = "Name of the target HTTP proxy"
  value       = google_compute_target_http_proxy.service_proxy.name
}

output "target_proxy_id" {
  description = "ID of the target HTTP proxy"
  value       = google_compute_target_http_proxy.service_proxy.id
}

output "forwarding_rule_name" {
  description = "Name of the global forwarding rule"
  value       = google_compute_global_forwarding_rule.service_forwarding_rule.name
}

output "forwarding_rule_id" {
  description = "ID of the global forwarding rule"
  value       = google_compute_global_forwarding_rule.service_forwarding_rule.id
}

# Health Check Information
output "health_check_name" {
  description = "Name of the health check"
  value       = google_compute_health_check.service_health_check.name
}

output "health_check_id" {
  description = "ID of the health check"
  value       = google_compute_health_check.service_health_check.id
}

output "health_check_self_link" {
  description = "Self-link of the health check"
  value       = google_compute_health_check.service_health_check.self_link
}

# Firewall Rules
output "firewall_rules" {
  description = "Information about created firewall rules"
  value = {
    http_rule = {
      name      = google_compute_firewall.allow_http.name
      id        = google_compute_firewall.allow_http.id
      direction = google_compute_firewall.allow_http.direction
      priority  = google_compute_firewall.allow_http.priority
    }
    health_check_rule = {
      name      = google_compute_firewall.allow_health_check.name
      id        = google_compute_firewall.allow_health_check.id
      direction = google_compute_firewall.allow_health_check.direction
      priority  = google_compute_firewall.allow_health_check.priority
    }
    ssh_rule = var.enable_ssh ? {
      name      = google_compute_firewall.allow_ssh[0].name
      id        = google_compute_firewall.allow_ssh[0].id
      direction = google_compute_firewall.allow_ssh[0].direction
      priority  = google_compute_firewall.allow_ssh[0].priority
    } : null
  }
}

# Test Client Information
output "test_client_name" {
  description = "Name of the test client instance (if created)"
  value       = var.create_test_client ? google_compute_instance.test_client[0].name : null
}

output "test_client_zone" {
  description = "Zone of the test client instance (if created)"
  value       = var.create_test_client ? google_compute_instance.test_client[0].zone : null
}

output "test_client_internal_ip" {
  description = "Internal IP of the test client instance (if created)"
  value       = var.create_test_client ? google_compute_instance.test_client[0].network_interface[0].network_ip : null
}

output "test_client_external_ip" {
  description = "External IP of the test client instance (if created)"
  value       = var.create_test_client && var.assign_external_ip ? (length(google_compute_instance.test_client[0].network_interface[0].access_config) > 0 ? google_compute_instance.test_client[0].network_interface[0].access_config[0].nat_ip : null) : null
}

# DNS Records Information
output "dns_records" {
  description = "Information about created DNS records"
  value = {
    service_a_record = {
      name     = google_dns_record_set.service_a_record.name
      type     = google_dns_record_set.service_a_record.type
      ttl      = google_dns_record_set.service_a_record.ttl
      rrdatas  = google_dns_record_set.service_a_record.rrdatas
    }
    service_srv_record = {
      name     = google_dns_record_set.service_srv_record.name
      type     = google_dns_record_set.service_srv_record.type
      ttl      = google_dns_record_set.service_srv_record.ttl
      rrdatas  = google_dns_record_set.service_srv_record.rrdatas
    }
    health_record = {
      name     = google_dns_record_set.health_record.name
      type     = google_dns_record_set.health_record.type
      ttl      = google_dns_record_set.health_record.ttl
      rrdatas  = google_dns_record_set.health_record.rrdatas
    }
    public_a_record = var.create_public_dns ? {
      name     = google_dns_record_set.public_a_record[0].name
      type     = google_dns_record_set.public_a_record[0].type
      ttl      = google_dns_record_set.public_a_record[0].ttl
      rrdatas  = google_dns_record_set.public_a_record[0].rrdatas
    } : null
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    service_url              = "http://${local.domain_name}/"
    health_check_url         = "http://health.${local.domain_name}/health"
    total_instances          = length(google_compute_instance_from_template.service_instances)
    instances_per_zone       = var.instances_per_zone
    load_balancing_policy    = var.locality_lb_policy
    health_check_interval    = var.health_check_interval
    connection_draining      = var.connection_draining_timeout
    external_access_enabled  = var.assign_external_ip
    public_dns_enabled       = var.create_public_dns
    test_client_enabled      = var.create_test_client
    ssh_enabled              = var.enable_ssh
  }
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to and testing the service"
  value = {
    dns_resolution_test = "nslookup ${local.domain_name}"
    service_test_curl   = "curl -s http://${local.domain_name}/ | jq ."
    health_check_test   = "curl -s http://${local.domain_name}/health | jq ."
    load_balancing_test = "for i in {1..10}; do curl -s http://${local.domain_name}/ | jq -r '.zone + \" - \" + .instance'; done"
    ssh_to_test_client  = var.create_test_client ? "gcloud compute ssh ${google_compute_instance.test_client[0].name} --zone=${google_compute_instance.test_client[0].zone}" : "Test client not created"
    test_script_path    = var.create_test_client ? "/home/test_service.sh" : "N/A"
  }
}

# Resource URLs for Management
output "management_urls" {
  description = "Google Cloud Console URLs for resource management"
  value = {
    compute_instances    = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
    load_balancer       = "https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers?project=${var.project_id}"
    dns_zones           = "https://console.cloud.google.com/net-services/dns/zones?project=${var.project_id}"
    vpc_networks        = "https://console.cloud.google.com/networking/networks/list?project=${var.project_id}"
    firewall_rules      = "https://console.cloud.google.com/networking/firewalls/list?project=${var.project_id}"
    health_checks       = "https://console.cloud.google.com/net-services/loadbalancing/list/healthChecks?project=${var.project_id}"
    backend_services    = "https://console.cloud.google.com/net-services/loadbalancing/list/backendServices?project=${var.project_id}"
    traffic_director    = "https://console.cloud.google.com/net-services/trafficdirector?project=${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Approximate monthly cost breakdown (USD, subject to change)"
  value = {
    compute_instances = "~$${length(google_compute_instance_from_template.service_instances) * 20}/month (e2-medium instances)"
    load_balancer    = "~$18/month (Global Load Balancer)"
    dns_zones        = "~$0.50/month per zone"
    vpc_network      = "$0/month (no charge for VPC)"
    data_transfer    = "Variable based on usage"
    total_estimated  = "~$${(length(google_compute_instance_from_template.service_instances) * 20) + 18 + (var.create_public_dns ? 1.0 : 0.5)}/month"
    note            = "Costs may vary based on region, usage patterns, and current pricing. Use Google Cloud Pricing Calculator for accurate estimates."
  }
}