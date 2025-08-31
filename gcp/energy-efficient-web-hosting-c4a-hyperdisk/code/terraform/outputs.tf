# Output values for Energy-Efficient Web Hosting with C4A and Hyperdisk
# These outputs provide important information about the deployed infrastructure
# for verification, monitoring, and integration with other systems

# Load Balancer Information
output "load_balancer_ip" {
  description = "External IP address of the load balancer for accessing the web application"
  value       = google_compute_global_forwarding_rule.web_forwarding_rule.ip_address
}

output "load_balancer_url" {
  description = "Complete URL for accessing the energy-efficient web application"
  value       = "http://${google_compute_global_forwarding_rule.web_forwarding_rule.ip_address}"
}

# Instance Information
output "web_server_instances" {
  description = "Details of C4A web server instances with Axion processors"
  value = {
    for idx, instance in google_compute_instance.web_servers : 
    instance.name => {
      id            = instance.id
      machine_type  = instance.machine_type
      zone          = instance.zone
      internal_ip   = instance.network_interface[0].network_ip
      external_ip   = instance.network_interface[0].access_config[0].nat_ip
      status        = instance.current_status
      self_link     = instance.self_link
    }
  }
}

output "instance_names" {
  description = "List of C4A instance names for reference and monitoring"
  value       = google_compute_instance.web_servers[*].name
}

output "instance_external_ips" {
  description = "External IP addresses of C4A instances for direct access"
  value       = [for instance in google_compute_instance.web_servers : instance.network_interface[0].access_config[0].nat_ip]
}

# Storage Information
output "hyperdisk_volumes" {
  description = "Information about Hyperdisk Balanced volumes for high-performance storage"
  value = {
    for idx, disk in google_compute_disk.web_data_disks :
    disk.name => {
      id                     = disk.id
      size_gb                = disk.size
      type                   = disk.type
      provisioned_iops       = disk.provisioned_iops
      provisioned_throughput = disk.provisioned_throughput
      zone                   = disk.zone
      self_link              = disk.self_link
    }
  }
}

# Network Information
output "vpc_network" {
  description = "VPC network information for the energy-efficient web hosting infrastructure"
  value = {
    id        = google_compute_network.energy_web_vpc.id
    name      = google_compute_network.energy_web_vpc.name
    self_link = google_compute_network.energy_web_vpc.self_link
  }
}

output "subnet_info" {
  description = "Subnet information for C4A instances"
  value = {
    id            = google_compute_subnetwork.energy_web_subnet.id
    name          = google_compute_subnetwork.energy_web_subnet.name
    ip_cidr_range = google_compute_subnetwork.energy_web_subnet.ip_cidr_range
    region        = google_compute_subnetwork.energy_web_subnet.region
    self_link     = google_compute_subnetwork.energy_web_subnet.self_link
  }
}

# Load Balancer Components
output "backend_service" {
  description = "Backend service configuration for load balancing across C4A instances"
  value = {
    id        = google_compute_backend_service.web_backend_service.id
    name      = google_compute_backend_service.web_backend_service.name
    protocol  = google_compute_backend_service.web_backend_service.protocol
    self_link = google_compute_backend_service.web_backend_service.self_link
  }
}

output "health_check" {
  description = "Health check configuration for monitoring C4A instance availability"
  value = {
    id                  = google_compute_health_check.web_health_check.id
    name                = google_compute_health_check.web_health_check.name
    check_interval_sec  = google_compute_health_check.web_health_check.check_interval_sec
    timeout_sec         = google_compute_health_check.web_health_check.timeout_sec
    healthy_threshold   = google_compute_health_check.web_health_check.healthy_threshold
    unhealthy_threshold = google_compute_health_check.web_health_check.unhealthy_threshold
    self_link           = google_compute_health_check.web_health_check.self_link
  }
}

output "instance_group" {
  description = "Instance group information for load balancing"
  value = {
    id        = google_compute_instance_group.web_instance_group.id
    name      = google_compute_instance_group.web_instance_group.name
    zone      = google_compute_instance_group.web_instance_group.zone
    size      = google_compute_instance_group.web_instance_group.size
    self_link = google_compute_instance_group.web_instance_group.self_link
  }
}

# Security Information
output "firewall_rules" {
  description = "Firewall rules for web traffic and health checks"
  value = {
    http_rule = {
      id        = google_compute_firewall.allow_http.id
      name      = google_compute_firewall.allow_http.name
      direction = google_compute_firewall.allow_http.direction
      self_link = google_compute_firewall.allow_http.self_link
    }
    https_rule = {
      id        = google_compute_firewall.allow_https.id
      name      = google_compute_firewall.allow_https.name
      direction = google_compute_firewall.allow_https.direction
      self_link = google_compute_firewall.allow_https.self_link
    }
    health_check_rule = {
      id        = google_compute_firewall.allow_health_checks.id
      name      = google_compute_firewall.allow_health_checks.name
      direction = google_compute_firewall.allow_health_checks.direction
      self_link = google_compute_firewall.allow_health_checks.self_link
    }
  }
}

# Monitoring Information
output "monitoring_dashboard" {
  description = "Cloud Monitoring dashboard for energy efficiency tracking"
  value = var.enable_monitoring_dashboard ? {
    id   = google_monitoring_dashboard.energy_efficiency_dashboard[0].id
    name = google_monitoring_dashboard.energy_efficiency_dashboard[0].dashboard_json
  } : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.energy_efficiency_dashboard[0].id}?project=${var.project_id}" : null
}

# Resource Naming Information
output "resource_naming" {
  description = "Information about resource naming convention and identifiers"
  value = {
    name_prefix   = local.name_prefix
    random_suffix = random_id.suffix.hex
    environment   = var.environment
  }
}

# Cost and Energy Efficiency Information
output "deployment_summary" {
  description = "Summary of deployed resources for cost and energy efficiency tracking"
  value = {
    instance_count     = var.instance_count
    machine_type       = var.machine_type
    total_disk_size_gb = var.instance_count * var.disk_size_gb
    region             = var.region
    zone               = var.zone
    architecture       = "ARM64 (Axion)"
    energy_efficiency  = "60% better than x86 instances"
    estimated_cost     = "$45-75 per month"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment and test functionality"
  value = {
    test_load_balancer = "curl -s http://${google_compute_global_forwarding_rule.web_forwarding_rule.ip_address}"
    check_instances    = "gcloud compute instances list --filter=\"name~web-server.*${random_id.suffix.hex}\" --format=\"table(name,status,machineType.scope(),zone.scope())\""
    check_disks       = "gcloud compute disks list --filter=\"name~web-data-disk.*${random_id.suffix.hex}\" --format=\"table(name,sizeGb,type,provisionedIops,provisionedThroughput)\""
    check_health      = "gcloud compute backend-services get-health ${google_compute_backend_service.web_backend_service.name} --global --format=\"table(status,instance.scope())\""
  }
}