# Output values for the gaming backend infrastructure

# Network and connectivity outputs
output "frontend_ip_address" {
  description = "Global static IP address for the gaming backend frontend"
  value       = google_compute_global_address.game_frontend_ip.address
}

output "frontend_url_http" {
  description = "HTTP URL for accessing the gaming backend"
  value       = "http://${google_compute_global_address.game_frontend_ip.address}"
}

output "frontend_url_https" {
  description = "HTTPS URL for accessing the gaming backend (if SSL configured)"
  value       = length(var.ssl_domains) > 0 ? "https://${var.ssl_domains[0]}" : "HTTPS not configured - no SSL domains provided"
}

# Redis instance outputs
output "redis_host" {
  description = "Private IP address of the Redis instance"
  value       = google_redis_instance.gaming_redis.host
  sensitive   = true
}

output "redis_port" {
  description = "Port number for Redis connections"
  value       = google_redis_instance.gaming_redis.port
}

output "redis_connection_string" {
  description = "Connection string for Redis instance (without auth)"
  value       = "${google_redis_instance.gaming_redis.host}:${google_redis_instance.gaming_redis.port}"
  sensitive   = true
}

output "redis_auth_string" {
  description = "Authentication string for Redis instance"
  value       = google_redis_instance.gaming_redis.auth_string
  sensitive   = true
}

output "redis_memory_size_gb" {
  description = "Memory size of the Redis instance in GB"
  value       = google_redis_instance.gaming_redis.memory_size_gb
}

# Storage outputs
output "game_assets_bucket_name" {
  description = "Name of the Cloud Storage bucket for game assets"
  value       = google_storage_bucket.game_assets.name
}

output "game_assets_bucket_url" {
  description = "URL of the Cloud Storage bucket for game assets"
  value       = google_storage_bucket.game_assets.url
}

output "game_assets_cdn_url" {
  description = "CDN URL for accessing game assets"
  value       = "http://${google_compute_global_address.game_frontend_ip.address}/assets/"
}

# Compute infrastructure outputs
output "instance_group_manager_name" {
  description = "Name of the managed instance group for game servers"
  value       = google_compute_instance_group_manager.game_server_group.name
}

output "instance_group_self_link" {
  description = "Self-link of the managed instance group"
  value       = google_compute_instance_group_manager.game_server_group.instance_group
}

output "instance_template_name" {
  description = "Name of the instance template for game servers"
  value       = google_compute_instance_template.game_server_template.name
}

output "autoscaler_name" {
  description = "Name of the autoscaler for game servers"
  value       = google_compute_autoscaler.game_server_autoscaler.name
}

# Load balancer outputs
output "backend_service_name" {
  description = "Name of the backend service for game servers"
  value       = google_compute_backend_service.game_backend.name
}

output "backend_bucket_name" {
  description = "Name of the backend bucket for static assets"
  value       = google_compute_backend_bucket.game_assets_backend.name
}

output "url_map_name" {
  description = "Name of the URL map for traffic routing"
  value       = google_compute_url_map.game_url_map.name
}

# Network security outputs
output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.gaming_network.name
}

output "subnet_name" {
  description = "Name of the subnet for game infrastructure"
  value       = google_compute_subnetwork.gaming_subnet.name
}

output "firewall_rules" {
  description = "Names of the created firewall rules"
  value = [
    google_compute_firewall.allow_game_traffic.name,
    google_compute_firewall.allow_health_checks.name
  ]
}

# SSL certificate outputs
output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (if created)"
  value       = length(var.ssl_domains) > 0 ? google_compute_managed_ssl_certificate.game_ssl_cert[0].name : "No SSL certificate created"
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate (if created)"
  value       = length(var.ssl_domains) > 0 ? google_compute_managed_ssl_certificate.game_ssl_cert[0].managed[0].status : "No SSL certificate created"
}

# Monitoring and operations outputs
output "health_check_name" {
  description = "Name of the health check for game servers"
  value       = google_compute_health_check.game_server_health.name
}

output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone"
  value       = var.zone
}

# Resource identifiers for external tools
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Connection information for game clients
output "game_client_endpoints" {
  description = "Connection endpoints for game clients"
  value = {
    http_endpoint     = "http://${google_compute_global_address.game_frontend_ip.address}"
    https_endpoint    = length(var.ssl_domains) > 0 ? "https://${var.ssl_domains[0]}" : null
    assets_endpoint   = "http://${google_compute_global_address.game_frontend_ip.address}/assets/"
    configs_endpoint  = "http://${google_compute_global_address.game_frontend_ip.address}/configs/"
    redis_internal_ip = google_redis_instance.gaming_redis.host
  }
  sensitive = true
}

# Operational commands for testing
output "redis_test_commands" {
  description = "Example Redis commands for testing gaming functionality"
  value = {
    connect_command = "redis-cli -h ${google_redis_instance.gaming_redis.host} -p ${google_redis_instance.gaming_redis.port} -a '<AUTH_STRING>'"
    test_leaderboard = "ZADD global_leaderboard 15000 'PlayerOne'"
    get_leaderboard = "ZREVRANGE global_leaderboard 0 9 WITHSCORES"
    set_player_data = "HSET player:12345 name 'PlayerOne' level 25 score 15000"
    get_player_data = "HGETALL player:12345"
  }
  sensitive = true
}

# Asset testing URLs
output "asset_test_urls" {
  description = "URLs for testing asset delivery through CDN"
  value = {
    game_config_url = "http://${google_compute_global_address.game_frontend_ip.address}/configs/game-config.json"
    sample_texture_url = "http://${google_compute_global_address.game_frontend_ip.address}/assets/textures/sample-texture.bin"
  }
}