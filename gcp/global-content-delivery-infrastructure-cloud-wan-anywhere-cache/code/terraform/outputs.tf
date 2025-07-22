# Output Definitions for Global Content Delivery Infrastructure
# This file defines all output values for verification and integration

# Project and Resource Identification
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "deployment_regions" {
  description = "Regions where infrastructure is deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    tertiary  = var.tertiary_region
  }
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Storage and Content Delivery
output "storage_bucket" {
  description = "Cloud Storage bucket information"
  value = {
    name         = google_storage_bucket.global_content_bucket.name
    url          = google_storage_bucket.global_content_bucket.url
    self_link    = google_storage_bucket.global_content_bucket.self_link
    location     = google_storage_bucket.global_content_bucket.location
    storage_class = google_storage_bucket.global_content_bucket.storage_class
  }
}

output "anywhere_caches" {
  description = "Anywhere Cache instances across regions"
  value = {
    primary = {
      zone              = google_storage_anywhere_cache.primary_cache.zone
      ttl               = google_storage_anywhere_cache.primary_cache.ttl
      anywhere_cache_id = google_storage_anywhere_cache.primary_cache.anywhere_cache_id
      state            = google_storage_anywhere_cache.primary_cache.state
    }
    secondary = {
      zone              = google_storage_anywhere_cache.secondary_cache.zone
      ttl               = google_storage_anywhere_cache.secondary_cache.ttl
      anywhere_cache_id = google_storage_anywhere_cache.secondary_cache.anywhere_cache_id
      state            = google_storage_anywhere_cache.secondary_cache.state
    }
    tertiary = {
      zone              = google_storage_anywhere_cache.tertiary_cache.zone
      ttl               = google_storage_anywhere_cache.tertiary_cache.ttl
      anywhere_cache_id = google_storage_anywhere_cache.tertiary_cache.anywhere_cache_id
      state            = google_storage_anywhere_cache.tertiary_cache.state
    }
  }
}

# Network Connectivity (Cloud WAN)
output "cloud_wan_hub" {
  description = "Cloud WAN hub information"
  value = {
    name      = google_network_connectivity_hub.enterprise_wan_hub.name
    id        = google_network_connectivity_hub.enterprise_wan_hub.id
    self_link = google_network_connectivity_hub.enterprise_wan_hub.self_link
    state     = google_network_connectivity_hub.enterprise_wan_hub.state
  }
}

output "cloud_wan_spokes" {
  description = "Cloud WAN spoke information across regions"
  value = {
    primary = {
      name      = google_network_connectivity_spoke.primary_spoke.name
      location  = google_network_connectivity_spoke.primary_spoke.location
      state     = google_network_connectivity_spoke.primary_spoke.state
    }
    secondary = {
      name      = google_network_connectivity_spoke.secondary_spoke.name
      location  = google_network_connectivity_spoke.secondary_spoke.location
      state     = google_network_connectivity_spoke.secondary_spoke.state
    }
    tertiary = {
      name      = google_network_connectivity_spoke.tertiary_spoke.name
      location  = google_network_connectivity_spoke.tertiary_spoke.location
      state     = google_network_connectivity_spoke.tertiary_spoke.state
    }
  }
}

# Compute Infrastructure
output "content_servers" {
  description = "Content server instances across regions"
  value = {
    primary = {
      name         = google_compute_instance.primary_content_server.name
      zone         = google_compute_instance.primary_content_server.zone
      machine_type = google_compute_instance.primary_content_server.machine_type
      external_ip  = google_compute_instance.primary_content_server.network_interface[0].access_config[0].nat_ip
      internal_ip  = google_compute_instance.primary_content_server.network_interface[0].network_ip
      self_link    = google_compute_instance.primary_content_server.self_link
    }
    secondary = {
      name         = google_compute_instance.secondary_content_server.name
      zone         = google_compute_instance.secondary_content_server.zone
      machine_type = google_compute_instance.secondary_content_server.machine_type
      external_ip  = google_compute_instance.secondary_content_server.network_interface[0].access_config[0].nat_ip
      internal_ip  = google_compute_instance.secondary_content_server.network_interface[0].network_ip
      self_link    = google_compute_instance.secondary_content_server.self_link
    }
    tertiary = {
      name         = google_compute_instance.tertiary_content_server.name
      zone         = google_compute_instance.tertiary_content_server.zone
      machine_type = google_compute_instance.tertiary_content_server.machine_type
      external_ip  = google_compute_instance.tertiary_content_server.network_interface[0].access_config[0].nat_ip
      internal_ip  = google_compute_instance.tertiary_content_server.network_interface[0].network_ip
      self_link    = google_compute_instance.tertiary_content_server.self_link
    }
  }
}

# Network Infrastructure
output "vpc_network" {
  description = "VPC network information"
  value = {
    name      = google_compute_network.content_delivery_network.name
    self_link = google_compute_network.content_delivery_network.self_link
    id        = google_compute_network.content_delivery_network.id
  }
}

# Load Balancer and CDN
output "global_load_balancer" {
  description = "Global load balancer configuration"
  value = {
    ip_address    = google_compute_global_address.content_delivery_ip.address
    url           = "http://${google_compute_global_address.content_delivery_ip.address}"
    backend_bucket = {
      name        = google_compute_backend_bucket.content_backend_bucket.name
      enable_cdn  = google_compute_backend_bucket.content_backend_bucket.enable_cdn
      self_link   = google_compute_backend_bucket.content_backend_bucket.self_link
    }
    url_map = {
      name      = google_compute_url_map.content_url_map.name
      self_link = google_compute_url_map.content_url_map.self_link
    }
    target_proxy = {
      name      = google_compute_target_http_proxy.content_target_proxy.name
      self_link = google_compute_target_http_proxy.content_target_proxy.self_link
    }
    forwarding_rule = {
      name      = google_compute_global_forwarding_rule.content_forwarding_rule.name
      self_link = google_compute_global_forwarding_rule.content_forwarding_rule.self_link
    }
  }
}

output "cdn_configuration" {
  description = "CDN configuration details"
  value = {
    enabled        = var.enable_cdn
    cache_mode     = var.cdn_cache_mode
    default_ttl    = var.cdn_default_ttl
    max_ttl        = var.cdn_max_ttl
    client_ttl     = var.cdn_client_ttl
  }
}

# Health Check and Instance Groups
output "health_check" {
  description = "Health check configuration"
  value = {
    name         = google_compute_health_check.content_health_check.name
    self_link    = google_compute_health_check.content_health_check.self_link
    timeout_sec  = google_compute_health_check.content_health_check.timeout_sec
    check_interval_sec = google_compute_health_check.content_health_check.check_interval_sec
  }
}

output "instance_groups" {
  description = "Instance group configurations"
  value = {
    primary = {
      name      = google_compute_instance_group.primary_instance_group.name
      zone      = google_compute_instance_group.primary_instance_group.zone
      self_link = google_compute_instance_group.primary_instance_group.self_link
      size      = google_compute_instance_group.primary_instance_group.size
    }
    secondary = {
      name      = google_compute_instance_group.secondary_instance_group.name
      zone      = google_compute_instance_group.secondary_instance_group.zone
      self_link = google_compute_instance_group.secondary_instance_group.self_link
      size      = google_compute_instance_group.secondary_instance_group.size
    }
    tertiary = {
      name      = google_compute_instance_group.tertiary_instance_group.name
      zone      = google_compute_instance_group.tertiary_instance_group.zone
      self_link = google_compute_instance_group.tertiary_instance_group.self_link
      size      = google_compute_instance_group.tertiary_instance_group.size
    }
  }
}

# Monitoring and Observability
output "monitoring" {
  description = "Monitoring configuration"
  value = {
    enabled           = var.enable_monitoring
    dashboard_created = var.enable_monitoring
    logging_enabled   = var.enable_logging
  }
}

# Sample Content Information
output "sample_content" {
  description = "Sample content information"
  value = var.create_sample_content ? {
    created = true
    files = [
      "index.html",
      "small-file.dat",
      "medium-file.dat", 
      "large-file.dat"
    ]
    access_url = "http://${google_compute_global_address.content_delivery_ip.address}/"
  } : {
    created = false
    files   = []
    access_url = ""
  }
}

# Security Configuration
output "security_configuration" {
  description = "Security configuration details"
  value = {
    uniform_bucket_access = var.enable_uniform_bucket_access
    public_access_enabled = var.enable_public_access
    deletion_protection   = var.enable_deletion_protection
    allowed_source_ranges = var.allowed_source_ranges
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    bucket_status = "gsutil ls -L -b gs://${google_storage_bucket.global_content_bucket.name}"
    cache_status  = "gcloud storage anywhere-caches list --bucket=${google_storage_bucket.global_content_bucket.name} --format='table(zone,state,ttl)'"
    wan_hub_status = "gcloud network-connectivity hubs describe ${google_network_connectivity_hub.enterprise_wan_hub.name}"
    wan_spokes_status = "gcloud network-connectivity spokes list --hub=${google_network_connectivity_hub.enterprise_wan_hub.name}"
    load_balancer_test = "curl -I http://${google_compute_global_address.content_delivery_ip.address}"
    compute_instances = "gcloud compute instances list --filter='labels.recipe=cloud-wan-anywhere-cache'"
    cdn_cache_test = "curl -v http://${google_compute_global_address.content_delivery_ip.address}/ 2>&1 | grep -i cache"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs (approximate)"
  value = {
    note = "Costs vary by region, usage patterns, and data transfer volumes"
    components = {
      storage_bucket = "~$0.026/GB/month for Standard storage"
      anywhere_cache = "~$0.04/GB-hour for SSD cache storage + compute costs"
      compute_instances = "~$100-200/month for 3 e2-standard-4 instances"
      load_balancer = "~$25/month + $0.008/GB processed"
      cloud_wan = "Contact Google Cloud sales for enterprise pricing"
      data_transfer = "~$0.12/GB for internet egress (first 1GB free)"
    }
  }
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to and testing the infrastructure"
  value = {
    load_balancer_url = "http://${google_compute_global_address.content_delivery_ip.address}"
    ssh_commands = {
      primary   = "gcloud compute ssh ${google_compute_instance.primary_content_server.name} --zone=${google_compute_instance.primary_content_server.zone}"
      secondary = "gcloud compute ssh ${google_compute_instance.secondary_content_server.name} --zone=${google_compute_instance.secondary_content_server.zone}"
      tertiary  = "gcloud compute ssh ${google_compute_instance.tertiary_content_server.name} --zone=${google_compute_instance.tertiary_content_server.zone}"
    }
    bucket_access = "gsutil ls gs://${google_storage_bucket.global_content_bucket.name}"
    monitoring_console = "https://console.cloud.google.com/monitoring/dashboards"
  }
}