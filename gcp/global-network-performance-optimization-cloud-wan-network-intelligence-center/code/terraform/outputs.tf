# Outputs for Global Network Performance Optimization Infrastructure
# This file defines all output values that provide important information about the deployed resources

# ============================================================================
# NETWORK INFORMATION
# ============================================================================

output "network_name" {
  description = "Name of the global VPC network"
  value       = google_compute_network.global_wan_network.name
}

output "network_id" {
  description = "ID of the global VPC network"
  value       = google_compute_network.global_wan_network.id
}

output "network_self_link" {
  description = "Self-link of the global VPC network"
  value       = google_compute_network.global_wan_network.self_link
}

output "regional_subnets" {
  description = "Information about regional subnets"
  value = {
    for k, v in google_compute_subnetwork.regional_subnets : k => {
      name         = v.name
      region       = v.region
      cidr_range   = v.ip_cidr_range
      gateway_ip   = v.gateway_address
      self_link    = v.self_link
      flow_logs_enabled = var.enable_flow_logs
    }
  }
}

# ============================================================================
# COMPUTE INSTANCES
# ============================================================================

output "web_servers" {
  description = "Information about regional web servers"
  value = {
    for k, v in google_compute_instance.regional_web_servers : k => {
      name          = v.name
      zone          = v.zone
      machine_type  = v.machine_type
      internal_ip   = v.network_interface[0].network_ip
      external_ip   = length(v.network_interface[0].access_config) > 0 ? v.network_interface[0].access_config[0].nat_ip : null
      self_link     = v.self_link
      status        = v.current_status
    }
  }
}

output "instance_groups" {
  description = "Information about instance groups for load balancing"
  value = {
    for k, v in google_compute_instance_group.web_instance_groups : k => {
      name      = v.name
      zone      = v.zone
      size      = v.size
      self_link = v.self_link
    }
  }
}

# ============================================================================
# LOAD BALANCER CONFIGURATION
# ============================================================================

output "load_balancer_ip" {
  description = "Global IP address of the HTTPS load balancer"
  value       = google_compute_global_forwarding_rule.web_https_forwarding_rule.ip_address
}

output "load_balancer_https_url" {
  description = "HTTPS URL for accessing the global load balancer"
  value       = "https://${google_compute_global_forwarding_rule.web_https_forwarding_rule.ip_address}"
}

output "load_balancer_http_url" {
  description = "HTTP URL for accessing the global load balancer"
  value       = "http://${google_compute_global_forwarding_rule.web_http_forwarding_rule.ip_address}"
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate"
  value = {
    name   = google_compute_managed_ssl_certificate.web_ssl_cert.name
    status = google_compute_managed_ssl_certificate.web_ssl_cert.certificate
    domains = google_compute_managed_ssl_certificate.web_ssl_cert.managed[0].domains
  }
}

output "backend_service" {
  description = "Information about the global backend service"
  value = {
    name      = google_compute_backend_service.web_backend_service.name
    protocol  = google_compute_backend_service.web_backend_service.protocol
    self_link = google_compute_backend_service.web_backend_service.self_link
    backends  = length(google_compute_backend_service.web_backend_service.backend)
  }
}

output "health_check" {
  description = "Information about the load balancer health check"
  value = {
    name              = google_compute_health_check.web_health_check.name
    check_interval    = google_compute_health_check.web_health_check.check_interval_sec
    timeout          = google_compute_health_check.web_health_check.timeout_sec
    healthy_threshold = google_compute_health_check.web_health_check.healthy_threshold
    self_link        = google_compute_health_check.web_health_check.self_link
  }
}

# ============================================================================
# NETWORK SECURITY
# ============================================================================

output "firewall_rules" {
  description = "Information about created firewall rules"
  value = {
    internal_communication = {
      name        = google_compute_firewall.allow_internal.name
      description = google_compute_firewall.allow_internal.description
      priority    = google_compute_firewall.allow_internal.priority
    }
    health_checks = {
      name        = google_compute_firewall.allow_health_checks.name
      description = google_compute_firewall.allow_health_checks.description
      priority    = google_compute_firewall.allow_health_checks.priority
    }
    ssh_access = {
      name        = google_compute_firewall.allow_ssh.name
      description = google_compute_firewall.allow_ssh.description
      priority    = google_compute_firewall.allow_ssh.priority
    }
  }
}

# ============================================================================
# MONITORING AND ANALYTICS
# ============================================================================

output "vpc_flow_logs_config" {
  description = "VPC Flow Logs configuration for Network Intelligence Center"
  value = var.enable_flow_logs ? {
    enabled           = true
    sampling_rate     = var.flow_logs_sampling
    aggregation_interval = var.flow_logs_interval
    metadata_fields   = "INCLUDE_ALL_METADATA"
  } : {
    enabled = false
  }
}

output "bigquery_dataset" {
  description = "BigQuery dataset for network analytics"
  value = var.enable_flow_logs ? {
    dataset_id = google_bigquery_dataset.network_analytics[0].dataset_id
    location   = google_bigquery_dataset.network_analytics[0].location
    self_link  = google_bigquery_dataset.network_analytics[0].self_link
  } : null
}

output "monitoring_dashboard" {
  description = "Cloud Monitoring dashboard for network performance"
  value = var.enable_monitoring ? {
    dashboard_id = google_monitoring_dashboard.network_performance_dashboard[0].id
    console_url  = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.network_performance_dashboard[0].id}"
  } : null
}

output "alert_policies" {
  description = "Monitoring alert policies"
  value = var.enable_monitoring && length(var.monitoring_notification_channels) > 0 ? {
    high_latency = {
      name        = google_monitoring_alert_policy.high_latency_alert[0].name
      enabled     = google_monitoring_alert_policy.high_latency_alert[0].enabled
      conditions  = length(google_monitoring_alert_policy.high_latency_alert[0].conditions)
    }
    lb_health = {
      name        = google_monitoring_alert_policy.lb_health_alert[0].name
      enabled     = google_monitoring_alert_policy.lb_health_alert[0].enabled
      conditions  = length(google_monitoring_alert_policy.lb_health_alert[0].conditions)
    }
  } : null
}

# ============================================================================
# NETWORK INTELLIGENCE CENTER LINKS
# ============================================================================

output "network_intelligence_center_urls" {
  description = "URLs for accessing Network Intelligence Center features"
  value = {
    topology = "https://console.cloud.google.com/net-intelligence/topology?project=${var.project_id}"
    connectivity_tests = "https://console.cloud.google.com/net-intelligence/connectivity/tests?project=${var.project_id}"
    performance_dashboard = "https://console.cloud.google.com/net-intelligence/performance/dashboard?project=${var.project_id}"
    network_analyzer = "https://console.cloud.google.com/net-intelligence/network-analyzer?project=${var.project_id}"
    flow_analyzer = "https://console.cloud.google.com/net-intelligence/flow-analyzer?project=${var.project_id}"
  }
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed global network infrastructure"
  value = {
    project_id        = var.project_id
    network_name      = google_compute_network.global_wan_network.name
    regions_deployed  = keys(var.regions)
    load_balancer_ip  = google_compute_global_forwarding_rule.web_https_forwarding_rule.ip_address
    total_instances   = length(google_compute_instance.regional_web_servers)
    flow_logs_enabled = var.enable_flow_logs
    monitoring_enabled = var.enable_monitoring
    unique_suffix     = local.unique_suffix
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Verify SSL certificate provisioning may take 15-30 minutes for managed certificates",
    "2. Access Network Intelligence Center topology at: https://console.cloud.google.com/net-intelligence/topology?project=${var.project_id}",
    "3. Test load balancer connectivity: curl -v http://${google_compute_global_forwarding_rule.web_http_forwarding_rule.ip_address}",
    "4. Monitor VPC Flow Logs in Cloud Logging for network telemetry data",
    "5. Review monitoring dashboard for network performance metrics",
    "6. Consider implementing Cloud WAN for production enterprise networks",
    "7. Configure connectivity tests in Network Intelligence Center for ongoing monitoring"
  ]
}

# ============================================================================
# TESTING AND VALIDATION
# ============================================================================

output "validation_commands" {
  description = "Commands for validating the deployment"
  value = [
    "# Test load balancer connectivity",
    "curl -v http://${google_compute_global_forwarding_rule.web_http_forwarding_rule.ip_address}",
    "",
    "# Check backend health status",
    "gcloud compute backend-services get-health ${google_compute_backend_service.web_backend_service.name} --global",
    "",
    "# View VPC network configuration", 
    "gcloud compute networks describe ${google_compute_network.global_wan_network.name}",
    "",
    "# List regional subnets",
    "gcloud compute networks subnets list --filter='network:${google_compute_network.global_wan_network.name}'",
    "",
    "# Check VPC Flow Logs status",
    join("\n", [for k, v in var.regions : "gcloud compute networks subnets describe ${local.network_name}-${k} --region=${v.name} --format='value(enableFlowLogs,logConfig)'"]),
    "",
    "# Monitor instances status",
    join("\n", [for k, v in google_compute_instance.regional_web_servers : "gcloud compute instances describe ${v.name} --zone=${v.zone} --format='value(status)'"])
  ]
}