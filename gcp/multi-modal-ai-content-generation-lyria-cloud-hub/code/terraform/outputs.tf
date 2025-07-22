# Outputs for Multi-Modal AI Content Generation Platform
# This file defines all output values that will be displayed after deployment

# ========================================
# PROJECT AND DEPLOYMENT INFO
# ========================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for resource naming"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# ========================================
# STORAGE INFRASTRUCTURE
# ========================================

output "content_bucket_name" {
  description = "Name of the primary content storage bucket"
  value       = google_storage_bucket.content_bucket.name
}

output "content_bucket_url" {
  description = "GCS URL of the content storage bucket"
  value       = google_storage_bucket.content_bucket.url
}

output "content_bucket_self_link" {
  description = "Self link of the content storage bucket"
  value       = google_storage_bucket.content_bucket.self_link
}

output "content_bucket_location" {
  description = "Location of the content storage bucket"
  value       = google_storage_bucket.content_bucket.location
}

# ========================================
# IAM AND SECURITY
# ========================================

output "service_account_email" {
  description = "Email address of the content AI service account"
  value       = google_service_account.content_ai_service_account.email
}

output "service_account_name" {
  description = "Name of the content AI service account"
  value       = google_service_account.content_ai_service_account.name
}

output "service_account_unique_id" {
  description = "Unique ID of the content AI service account"
  value       = google_service_account.content_ai_service_account.unique_id
}

output "service_account_key_id" {
  description = "ID of the service account key (for reference only)"
  value       = google_service_account_key.content_ai_key.name
  sensitive   = true
}

# ========================================
# CLOUD FUNCTIONS
# ========================================

output "music_generation_function_name" {
  description = "Name of the Lyria music generation function"
  value       = google_cloudfunctions2_function.music_generation.name
}

output "music_generation_function_url" {
  description = "URL of the Lyria music generation function"
  value       = google_cloudfunctions2_function.music_generation.service_config[0].uri
}

output "video_generation_function_name" {
  description = "Name of the Veo video generation function"
  value       = google_cloudfunctions2_function.video_generation.name
}

output "video_generation_function_url" {
  description = "URL of the Veo video generation function"
  value       = google_cloudfunctions2_function.video_generation.service_config[0].uri
}

output "quality_assessment_function_name" {
  description = "Name of the quality assessment function"
  value       = google_cloudfunctions2_function.quality_assessment.name
}

output "quality_assessment_function_url" {
  description = "URL of the quality assessment function"
  value       = google_cloudfunctions2_function.quality_assessment.service_config[0].uri
}

# ========================================
# CLOUD RUN ORCHESTRATION
# ========================================

output "orchestrator_service_name" {
  description = "Name of the content orchestration Cloud Run service"
  value       = google_cloud_run_v2_service.content_orchestrator.name
}

output "orchestrator_service_url" {
  description = "URL of the content orchestration service"
  value       = google_cloud_run_v2_service.content_orchestrator.uri
}

output "orchestrator_service_id" {
  description = "Full resource ID of the orchestrator service"
  value       = google_cloud_run_v2_service.content_orchestrator.id
}

output "orchestrator_generation_endpoint" {
  description = "Complete endpoint URL for content generation requests"
  value       = "${google_cloud_run_v2_service.content_orchestrator.uri}/generate"
}

output "orchestrator_health_endpoint" {
  description = "Health check endpoint for the orchestrator service"
  value       = "${google_cloud_run_v2_service.content_orchestrator.uri}/health"
}

# ========================================
# MONITORING AND OBSERVABILITY
# ========================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "custom_metrics" {
  description = "List of custom metrics created for monitoring"
  value = var.enable_monitoring ? [
    google_monitoring_metric_descriptor.content_generation_requests[0].type,
    google_monitoring_metric_descriptor.content_generation_latency[0].type
  ] : []
}

output "alert_policies" {
  description = "List of alert policies created"
  value = var.enable_monitoring && length(var.notification_channels) > 0 ? [
    google_monitoring_alert_policy.high_error_rate[0].name,
    google_monitoring_alert_policy.orchestrator_availability[0].name
  ] : []
}

# ========================================
# NETWORK AND SECURITY
# ========================================

output "vpc_network_name" {
  description = "Name of the VPC network (if created for production)"
  value       = var.environment == "prod" ? google_compute_network.content_vpc[0].name : null
}

output "subnet_name" {
  description = "Name of the subnet (if created for production)"
  value       = var.environment == "prod" ? google_compute_subnetwork.content_subnet[0].name : null
}

output "security_policy_name" {
  description = "Name of the Cloud Armor security policy (if created for production)"
  value       = var.environment == "prod" ? google_compute_security_policy.content_security_policy[0].name : null
}

# ========================================
# DEPLOYMENT CONFIGURATION
# ========================================

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = var.apis_to_enable
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "deletion_protection" {
  description = "Whether deletion protection is enabled for critical resources"
  value       = var.deletion_protection
}

# ========================================
# USAGE INSTRUCTIONS
# ========================================

output "getting_started_instructions" {
  description = "Instructions for getting started with the platform"
  value = <<-EOT
    Multi-Modal AI Content Generation Platform Deployed Successfully!
    
    Platform Endpoints:
    - Content Generation: ${google_cloud_run_v2_service.content_orchestrator.uri}/generate
    - Health Check: ${google_cloud_run_v2_service.content_orchestrator.uri}/health
    - Music Generation: ${google_cloudfunctions2_function.music_generation.service_config[0].uri}
    - Video Generation: ${google_cloudfunctions2_function.video_generation.service_config[0].uri}
    - Quality Assessment: ${google_cloudfunctions2_function.quality_assessment.service_config[0].uri}
    
    Storage:
    - Content Bucket: gs://${google_storage_bucket.content_bucket.name}
    
    Next Steps:
    1. Upload function source code to the appropriate bucket paths
    2. Deploy the container image for the orchestrator service
    3. Test the content generation endpoints
    4. Configure monitoring alerts (if notification channels are provided)
    5. Set up CI/CD pipelines for function and service updates
    
    Authentication:
    - Service Account: ${google_service_account.content_ai_service_account.email}
    - Use the service account key for API authentication
    
    For production use:
    - Configure proper IAM permissions
    - Set up notification channels for monitoring
    - Review security policies and network configuration
    - Enable deletion protection for critical resources
  EOT
}

output "example_request" {
  description = "Example curl command for testing content generation"
  value = <<-EOT
    # Example content generation request:
    curl -X POST ${google_cloud_run_v2_service.content_orchestrator.uri}/generate \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -d '{
        "prompt": "Create an inspiring tech product launch presentation",
        "style": "professional",
        "duration": 45
      }'
  EOT
}

# ========================================
# COST AND RESOURCE INFORMATION
# ========================================

output "resource_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    storage = {
      bucket_name = google_storage_bucket.content_bucket.name
      location    = google_storage_bucket.content_bucket.location
      purpose     = "Primary storage for generated content assets"
    }
    compute = {
      cloud_functions = {
        music_generation    = google_cloudfunctions2_function.music_generation.name
        video_generation    = google_cloudfunctions2_function.video_generation.name
        quality_assessment  = google_cloudfunctions2_function.quality_assessment.name
      }
      cloud_run = {
        orchestrator = google_cloud_run_v2_service.content_orchestrator.name
      }
    }
    ai_ml = {
      vertex_ai_access = "Enabled through service account permissions"
      lyria_integration = "Via music generation function"
      veo_integration = "Via video generation function"
    }
    monitoring = {
      enabled = var.enable_monitoring
      custom_metrics = var.enable_monitoring ? 2 : 0
      alert_policies = var.enable_monitoring && length(var.notification_channels) > 0 ? 2 : 0
    }
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = <<-EOT
    Estimated Monthly Costs (USD, varies by usage):
    
    Base Infrastructure:
    - Cloud Storage (100GB): ~$2.00
    - Cloud Functions (1M requests): ~$0.40
    - Cloud Run (10M requests): ~$24.00
    - Cloud Monitoring: ~$0.15
    
    AI/ML Services (usage-dependent):
    - Vertex AI Lyria 2 Music Generation: $0.02-0.05 per minute of audio
    - Vertex AI Veo 3 Video Generation: $0.10-0.20 per second of video
    - Text-to-Speech: ~$16.00 per 1M characters
    
    Total Base: ~$26.55/month
    AI Usage: Varies significantly based on generation volume
    
    Note: Actual costs depend on usage patterns, data storage, and generation frequency.
    Enable billing alerts to monitor costs during development and testing.
  EOT
}