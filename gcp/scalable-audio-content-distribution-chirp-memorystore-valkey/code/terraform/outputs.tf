# Output values for the scalable audio content distribution infrastructure
# These outputs provide essential information for accessing and managing the deployed resources

# Project and Region Information
output "project_id" {
  description = "Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

# Networking Outputs
output "network_name" {
  description = "Name of the VPC network created for the audio distribution platform"
  value       = google_compute_network.audio_network.name
}

output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.audio_network.id
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.audio_network.self_link
}

output "memorystore_subnet_name" {
  description = "Name of the subnet created for Memorystore connectivity"
  value       = google_compute_subnetwork.memorystore_subnet.name
}

output "memorystore_subnet_cidr" {
  description = "CIDR range of the Memorystore subnet"
  value       = google_compute_subnetwork.memorystore_subnet.ip_cidr_range
}

# Memorystore Valkey Outputs
output "valkey_instance_id" {
  description = "Instance ID of the Memorystore Valkey instance"
  value       = google_memorystore_instance.valkey_cache.instance_id
}

output "valkey_instance_name" {
  description = "Full resource name of the Memorystore Valkey instance"
  value       = google_memorystore_instance.valkey_cache.name
}

output "valkey_host" {
  description = "Host address of the Valkey instance for application connections"
  value       = google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address
  sensitive   = false
}

output "valkey_port" {
  description = "Port number for connecting to the Valkey instance"
  value       = "6379"
}

output "valkey_connection_string" {
  description = "Connection string for the Valkey instance"
  value       = "${google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address}:6379"
  sensitive   = false
}

output "valkey_auth_enabled" {
  description = "Whether authentication is enabled for the Valkey instance"
  value       = var.enable_valkey_auth
}

output "valkey_encryption_enabled" {
  description = "Whether transit encryption is enabled for the Valkey instance"
  value       = var.enable_valkey_encryption
}

output "valkey_state" {
  description = "Current state of the Valkey instance"
  value       = google_memorystore_instance.valkey_cache.state
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio assets"
  value       = google_storage_bucket.audio_bucket.name
}

output "storage_bucket_url" {
  description = "Public URL of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.url
}

output "storage_bucket_self_link" {
  description = "Self link of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.self_link
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_bucket.storage_class
}

# Cloud Functions Outputs
output "audio_processor_function_name" {
  description = "Name of the audio processor Cloud Function"
  value       = google_cloudfunctions2_function.audio_processor.name
}

output "audio_processor_function_url" {
  description = "HTTP trigger URL for the audio processor function"
  value       = google_cloudfunctions2_function.audio_processor.service_config[0].uri
  sensitive   = false
}

output "audio_processor_function_location" {
  description = "Location of the audio processor Cloud Function"
  value       = google_cloudfunctions2_function.audio_processor.location
}

output "audio_processor_function_memory" {
  description = "Memory allocation for the audio processor function"
  value       = google_cloudfunctions2_function.audio_processor.service_config[0].available_memory
}

output "audio_processor_function_timeout" {
  description = "Timeout setting for the audio processor function"
  value       = google_cloudfunctions2_function.audio_processor.service_config[0].timeout_seconds
}

# Cloud Run Outputs
output "audio_management_service_name" {
  description = "Name of the audio management Cloud Run service"
  value       = google_cloud_run_v2_service.audio_management.name
}

output "audio_management_service_url" {
  description = "Public URL of the audio management service"
  value       = google_cloud_run_v2_service.audio_management.uri
  sensitive   = false
}

output "audio_management_service_location" {
  description = "Location of the audio management Cloud Run service"
  value       = google_cloud_run_v2_service.audio_management.location
}

# CDN and Load Balancing Outputs
output "cdn_ip_address" {
  description = "Global static IP address for the CDN"
  value       = google_compute_global_address.cdn_ip.address
}

output "cdn_ip_name" {
  description = "Name of the global static IP address"
  value       = google_compute_global_address.cdn_ip.name
}

output "cdn_backend_bucket_name" {
  description = "Name of the CDN backend bucket"
  value       = google_compute_backend_bucket.audio_backend.name
}

output "cdn_url_map_name" {
  description = "Name of the CDN URL map"
  value       = google_compute_url_map.audio_cdn_map.name
}

output "cdn_https_proxy_name" {
  description = "Name of the HTTPS target proxy"
  value       = google_compute_target_https_proxy.audio_https_proxy.name
}

output "cdn_ssl_certificate_name" {
  description = "Name of the managed SSL certificate"
  value       = google_compute_managed_ssl_certificate.audio_ssl_cert.name
}

output "cdn_https_url" {
  description = "HTTPS URL for accessing content through the CDN"
  value       = "https://${google_compute_global_address.cdn_ip.address}"
}

output "cdn_http_url" {
  description = "HTTP URL that redirects to HTTPS"
  value       = "http://${google_compute_global_address.cdn_ip.address}"
}

# Service Account Outputs
output "tts_service_account_email" {
  description = "Email address of the Text-to-Speech service account"
  value       = google_service_account.tts_service_account.email
}

output "function_service_account_email" {
  description = "Email address of the Cloud Functions service account"
  value       = google_service_account.function_service_account.email
}

output "cloudrun_service_account_email" {
  description = "Email address of the Cloud Run service account"
  value       = google_service_account.cloudrun_service_account.email
}

# API and Configuration Outputs
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the project"
  value       = var.enable_apis
}

output "default_tts_voice_config" {
  description = "Default Text-to-Speech voice configuration"
  value       = var.tts_voice_config
  sensitive   = false
}

output "default_tts_audio_config" {
  description = "Default Text-to-Speech audio configuration"
  value       = var.tts_audio_config
  sensitive   = false
}

# Monitoring and Logging Outputs
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.audio_dashboard[0].id : null
}

output "logging_sink_name" {
  description = "Name of the audit logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.audio_audit_sink[0].name : null
}

output "logging_sink_destination" {
  description = "Destination of the audit logging sink (if enabled)"
  value       = var.enable_logging ? google_logging_project_sink.audio_audit_sink[0].destination : null
}

# Usage and Testing Information
output "curl_test_command" {
  description = "Sample curl command to test the audio processor function"
  value = <<-EOT
curl -X POST "${google_cloudfunctions2_function.audio_processor.service_config[0].uri}" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hello, this is a test of our scalable audio content distribution platform.",
    "voiceConfig": {
      "languageCode": "en-US",
      "voiceName": "en-US-Casual",
      "gender": "NEUTRAL"
    }
  }'
EOT
}

output "management_api_test_command" {
  description = "Sample curl command to test the management API"
  value = <<-EOT
# Health check
curl "${google_cloud_run_v2_service.audio_management.uri}/health"

# Generate audio
curl -X POST "${google_cloud_run_v2_service.audio_management.uri}/api/audio/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Welcome to our audio distribution platform.",
    "voiceConfig": {
      "languageCode": "en-US",
      "voiceName": "en-US-Casual"
    }
  }'
EOT
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources and their key information"
  value = {
    project_id                = var.project_id
    region                    = var.region
    environment               = var.environment
    
    # Network
    network_name              = google_compute_network.audio_network.name
    
    # Storage
    bucket_name               = google_storage_bucket.audio_bucket.name
    bucket_url                = google_storage_bucket.audio_bucket.url
    
    # Caching
    valkey_instance_id        = google_memorystore_instance.valkey_cache.instance_id
    valkey_connection         = "${google_memorystore_instance.valkey_cache.endpoints[0].connections[0].psc_auto_connection[0].ip_address}:6379"
    
    # Compute
    function_url              = google_cloudfunctions2_function.audio_processor.service_config[0].uri
    cloudrun_url              = google_cloud_run_v2_service.audio_management.uri
    
    # CDN
    cdn_ip                    = google_compute_global_address.cdn_ip.address
    cdn_https_url             = "https://${google_compute_global_address.cdn_ip.address}"
    
    # Monitoring
    monitoring_enabled        = var.enable_monitoring
    logging_enabled           = var.enable_logging
    
    # Security
    valkey_auth_enabled       = var.enable_valkey_auth
    valkey_encryption_enabled = var.enable_valkey_encryption
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure (USD)"
  value = {
    memorystore_valkey = "~$50-150 (depending on instance size and usage)"
    cloud_storage      = "~$5-25 (depending on storage volume and requests)"
    cloud_functions    = "~$10-50 (depending on invocation volume)"
    cloud_run          = "~$10-30 (depending on CPU/memory usage)"
    cloud_cdn          = "~$5-20 (depending on bandwidth usage)"
    networking         = "~$5-15 (VPC, load balancing)"
    monitoring_logging = "~$5-15 (depending on log volume)"
    total_estimated    = "~$90-305 per month"
    note              = "Costs vary significantly based on usage patterns. Monitor actual usage for accurate billing."
  }
}

# Next Steps and Recommendations
output "post_deployment_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the audio processor function using the provided curl command",
    "2. Configure a custom domain for the CDN endpoint",
    "3. Set up SSL certificate for the custom domain",
    "4. Configure monitoring alerts for key metrics",
    "5. Review and adjust cache TTL settings based on usage patterns",
    "6. Implement authentication if required for production use",
    "7. Set up automated backups for critical data",
    "8. Review security settings and firewall rules",
    "9. Consider setting up multi-region deployment for global availability",
    "10. Optimize costs by monitoring usage and adjusting resource sizes"
  ]
}