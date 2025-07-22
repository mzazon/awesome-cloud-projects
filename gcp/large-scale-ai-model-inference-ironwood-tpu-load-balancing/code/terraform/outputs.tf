# Outputs for Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing
# This file defines outputs that provide important information about the deployed infrastructure

# Load Balancer Information
output "load_balancer_ip" {
  description = "Global IP address of the AI inference load balancer"
  value       = google_compute_global_address.ai_inference_ip.address
  sensitive   = false
}

output "load_balancer_url" {
  description = "Complete URL for accessing the AI inference API"
  value       = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https://${google_compute_global_address.ai_inference_ip.address}" : "http://${google_compute_global_address.ai_inference_ip.address}"
  sensitive   = false
}

output "ssl_certificate_domains" {
  description = "Domains configured for SSL certificate (if SSL is enabled)"
  value       = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? var.ssl_certificate_domains : []
  sensitive   = false
}

# TPU Resource Information
output "tpu_small_pod_name" {
  description = "Name of the small TPU pod (v7-256)"
  value       = var.enable_small_tpu ? google_tpu_v2_vm.small_tpu[0].name : null
  sensitive   = false
}

output "tpu_medium_pod_name" {
  description = "Name of the medium TPU pod (v7-1024)"
  value       = var.enable_medium_tpu ? google_tpu_v2_vm.medium_tpu[0].name : null
  sensitive   = false
}

output "tpu_large_pod_name" {
  description = "Name of the large TPU pod (v7-9216)"
  value       = var.enable_large_tpu ? google_tpu_v2_vm.large_tpu[0].name : null
  sensitive   = false
}

output "tpu_pods_status" {
  description = "Status and configuration of all TPU pods"
  value = {
    small = var.enable_small_tpu ? {
      name             = google_tpu_v2_vm.small_tpu[0].name
      accelerator_type = google_tpu_v2_vm.small_tpu[0].accelerator_type
      zone             = google_tpu_v2_vm.small_tpu[0].zone
    } : null
    medium = var.enable_medium_tpu ? {
      name             = google_tpu_v2_vm.medium_tpu[0].name
      accelerator_type = google_tpu_v2_vm.medium_tpu[0].accelerator_type
      zone             = google_tpu_v2_vm.medium_tpu[0].zone
    } : null
    large = var.enable_large_tpu ? {
      name             = google_tpu_v2_vm.large_tpu[0].name
      accelerator_type = google_tpu_v2_vm.large_tpu[0].accelerator_type
      zone             = google_tpu_v2_vm.large_tpu[0].zone
    } : null
  }
  sensitive = false
}

# Vertex AI Endpoints
output "vertex_ai_model_name" {
  description = "Name of the deployed Vertex AI model"
  value       = google_vertex_ai_model.inference_model.name
  sensitive   = false
}

output "vertex_ai_endpoints" {
  description = "Details of all Vertex AI endpoints"
  value = {
    small = var.enable_small_tpu ? {
      name         = google_vertex_ai_endpoint.small_endpoint[0].name
      display_name = google_vertex_ai_endpoint.small_endpoint[0].display_name
      location     = google_vertex_ai_endpoint.small_endpoint[0].location
    } : null
    medium = var.enable_medium_tpu ? {
      name         = google_vertex_ai_endpoint.medium_endpoint[0].name
      display_name = google_vertex_ai_endpoint.medium_endpoint[0].display_name
      location     = google_vertex_ai_endpoint.medium_endpoint[0].location
    } : null
    large = var.enable_large_tpu ? {
      name         = google_vertex_ai_endpoint.large_endpoint[0].name
      display_name = google_vertex_ai_endpoint.large_endpoint[0].display_name
      location     = google_vertex_ai_endpoint.large_endpoint[0].location
    } : null
  }
  sensitive = false
}

# Network and Security Information
output "vpc_network_name" {
  description = "Name of the VPC network created for TPU resources"
  value       = google_compute_network.tpu_network.name
  sensitive   = false
}

output "vpc_subnet_name" {
  description = "Name of the subnet created for TPU resources"
  value       = google_compute_subnetwork.tpu_subnet.name
  sensitive   = false
}

output "service_account_email" {
  description = "Email of the service account used for TPU operations"
  value       = google_service_account.tpu_inference.email
  sensitive   = false
}

# Caching and Storage Information
output "redis_cache_instance" {
  description = "Details of the Redis cache instance (if enabled)"
  value = var.enable_redis_cache ? {
    name               = google_redis_instance.inference_cache[0].name
    memory_size_gb     = google_redis_instance.inference_cache[0].memory_size_gb
    region             = google_redis_instance.inference_cache[0].region
    host               = google_redis_instance.inference_cache[0].host
    port               = google_redis_instance.inference_cache[0].port
    auth_string        = google_redis_instance.inference_cache[0].auth_string
  } : null
  sensitive = true
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID for analytics (if enabled)"
  value       = var.enable_bigquery_analytics ? google_bigquery_dataset.tpu_analytics[0].dataset_id : null
  sensitive   = false
}

# Monitoring and Analytics
output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.tpu_dashboard[0].id}?project=${var.project_id}" : null
  sensitive   = false
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for metrics streaming"
  value       = var.enable_monitoring ? google_pubsub_topic.tpu_metrics_stream[0].name : null
  sensitive   = false
}

# Load Balancer Backend Information
output "backend_services" {
  description = "Details of backend services for different TPU tiers"
  value = {
    small = var.enable_small_tpu ? {
      name        = google_compute_backend_service.small_backend[0].name
      protocol    = google_compute_backend_service.small_backend[0].protocol
      enable_cdn  = google_compute_backend_service.small_backend[0].enable_cdn
      timeout_sec = google_compute_backend_service.small_backend[0].timeout_sec
    } : null
    medium = var.enable_medium_tpu ? {
      name        = google_compute_backend_service.medium_backend[0].name
      protocol    = google_compute_backend_service.medium_backend[0].protocol
      enable_cdn  = google_compute_backend_service.medium_backend[0].enable_cdn
      timeout_sec = google_compute_backend_service.medium_backend[0].timeout_sec
    } : null
    large = var.enable_large_tpu ? {
      name        = google_compute_backend_service.large_backend[0].name
      protocol    = google_compute_backend_service.large_backend[0].protocol
      enable_cdn  = google_compute_backend_service.large_backend[0].enable_cdn
      timeout_sec = google_compute_backend_service.large_backend[0].timeout_sec
    } : null
  }
  sensitive = false
}

# Auto-scaling Configuration
output "autoscaling_configuration" {
  description = "Auto-scaling configuration for each TPU tier"
  value = {
    small = var.enable_small_tpu ? {
      min_replicas              = var.min_replicas_small
      max_replicas              = var.max_replicas_small
      target_cpu_utilization    = var.auto_scaling_target_cpu_utilization
      autoscaler_name          = google_compute_autoscaler.small_tpu_autoscaler[0].name
    } : null
    medium = var.enable_medium_tpu ? {
      min_replicas              = var.min_replicas_medium
      max_replicas              = var.max_replicas_medium
      target_cpu_utilization    = var.auto_scaling_target_cpu_utilization
      autoscaler_name          = google_compute_autoscaler.medium_tpu_autoscaler[0].name
    } : null
    large = var.enable_large_tpu ? {
      min_replicas              = var.min_replicas_large
      max_replicas              = var.max_replicas_large
      target_cpu_utilization    = var.auto_scaling_target_cpu_utilization
      autoscaler_name          = google_compute_autoscaler.large_tpu_autoscaler[0].name
    } : null
  }
  sensitive = false
}

# Health Check Information
output "health_check_configuration" {
  description = "Health check configuration details"
  value = {
    name                = google_compute_health_check.tpu_health_check.name
    check_interval_sec  = google_compute_health_check.tpu_health_check.check_interval_sec
    timeout_sec         = google_compute_health_check.tpu_health_check.timeout_sec
    healthy_threshold   = google_compute_health_check.tpu_health_check.healthy_threshold
    unhealthy_threshold = google_compute_health_check.tpu_health_check.unhealthy_threshold
    request_path        = google_compute_health_check.tpu_health_check.http_health_check[0].request_path
    port                = google_compute_health_check.tpu_health_check.http_health_check[0].port
  }
  sensitive = false
}

# Cost Management Information
output "budget_configuration" {
  description = "Budget and cost monitoring configuration"
  value = var.enable_monitoring ? {
    display_name        = google_billing_budget.tpu_budget[0].display_name
    budget_amount       = var.budget_amount
    threshold_percent   = var.budget_threshold_percent
    notification_email  = var.notification_email
  } : null
  sensitive = false
}

# API Endpoints for Testing
output "api_endpoints" {
  description = "API endpoints for testing different inference workloads"
  value = {
    simple_inference  = "${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/simple/predict"
    standard_inference = "${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/v1/predict"
    complex_inference = "${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/complex/predict"
    health_check     = "${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/health"
  }
  sensitive = false
}

# Resource Names Summary
output "resource_names_summary" {
  description = "Summary of all major resource names for easy reference"
  value = {
    project_id          = var.project_id
    region              = var.region
    zone                = var.zone
    name_prefix         = local.name_prefix
    name_suffix         = local.name_suffix
    model_name          = var.model_name
    environment         = var.environment
    vpc_network         = google_compute_network.tpu_network.name
    load_balancer_ip    = google_compute_global_address.ai_inference_ip.address
    service_account     = google_service_account.tpu_inference.email
  }
  sensitive = false
}

# Deployment Status
output "deployment_status" {
  description = "Status of key infrastructure components"
  value = {
    tpu_small_enabled   = var.enable_small_tpu
    tpu_medium_enabled  = var.enable_medium_tpu
    tpu_large_enabled   = var.enable_large_tpu
    ssl_enabled         = var.enable_ssl
    monitoring_enabled  = var.enable_monitoring
    redis_cache_enabled = var.enable_redis_cache
    cdn_enabled         = var.enable_cdn
    bigquery_enabled    = var.enable_bigquery_analytics
  }
  sensitive = false
}

# Performance Optimization Tips
output "optimization_tips" {
  description = "Performance optimization recommendations based on current configuration"
  value = {
    message = "To optimize performance, consider the following recommendations based on your configuration:"
    recommendations = [
      var.enable_small_tpu ? "Small TPU (v7-256) is enabled - route simple queries to /simple/* paths for cost efficiency" : null,
      var.enable_medium_tpu ? "Medium TPU (v7-1024) is enabled - use for standard inference workloads" : null,
      var.enable_large_tpu ? "Large TPU (v7-9216) is enabled - route complex queries to /complex/* paths for maximum performance" : null,
      var.enable_redis_cache ? "Redis cache is enabled - implement response caching for repeated queries" : "Consider enabling Redis cache for improved response times",
      var.enable_cdn ? "CDN is enabled - static responses will be cached globally" : "Consider enabling CDN for better global performance",
      var.enable_monitoring ? "Monitoring is enabled - review dashboards for optimization opportunities" : "Consider enabling monitoring for performance insights"
    ]
  }
  sensitive = false
}

# Connection Commands
output "connection_commands" {
  description = "Useful commands for connecting to and managing the infrastructure"
  value = {
    connect_to_small_tpu = var.enable_small_tpu ? "gcloud compute tpus tpu-vm ssh ${google_tpu_v2_vm.small_tpu[0].name} --zone=${var.zone}" : null
    connect_to_medium_tpu = var.enable_medium_tpu ? "gcloud compute tpus tpu-vm ssh ${google_tpu_v2_vm.medium_tpu[0].name} --zone=${var.zone}" : null
    connect_to_large_tpu = var.enable_large_tpu ? "gcloud compute tpus tpu-vm ssh ${google_tpu_v2_vm.large_tpu[0].name} --zone=${var.zone}" : null
    test_inference_api = "curl -X POST ${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/v1/predict -H 'Content-Type: application/json' -d '{\"instances\": [{\"text\": \"Test inference request\"}]}'"
    view_logs = "gcloud logging read 'resource.type=\"gce_instance\" AND jsonPayload.component=\"tpu-inference\"' --limit=50 --format=json"
    check_health = "curl ${var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? "https" : "http"}://${google_compute_global_address.ai_inference_ip.address}/health"
  }
  sensitive = false
}