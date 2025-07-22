# GPU-Accelerated Multi-Agent AI Systems - Terraform Outputs
# This file defines all output values that will be displayed after deployment

# Project and Basic Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# Networking Outputs
output "vpc_network_id" {
  description = "ID of the VPC network created for the multi-agent system"
  value       = google_compute_network.agent_network.id
}

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.agent_network.name
}

output "subnet_id" {
  description = "ID of the subnet created for agent resources"
  value       = google_compute_subnetwork.agent_subnet.id
}

output "subnet_cidr" {
  description = "CIDR range of the agent subnet"
  value       = google_compute_subnetwork.agent_subnet.ip_cidr_range
}

# Cloud Run Service Outputs
output "vision_agent_url" {
  description = "URL of the Vision Agent Cloud Run service"
  value       = google_cloud_run_v2_service.vision_agent.uri
  sensitive   = false
}

output "vision_agent_name" {
  description = "Name of the Vision Agent service"
  value       = google_cloud_run_v2_service.vision_agent.name
}

output "language_agent_url" {
  description = "URL of the Language Agent Cloud Run service"
  value       = google_cloud_run_v2_service.language_agent.uri
  sensitive   = false
}

output "language_agent_name" {
  description = "Name of the Language Agent service"
  value       = google_cloud_run_v2_service.language_agent.name
}

output "reasoning_agent_url" {
  description = "URL of the Reasoning Agent Cloud Run service"
  value       = google_cloud_run_v2_service.reasoning_agent.uri
  sensitive   = false
}

output "reasoning_agent_name" {
  description = "Name of the Reasoning Agent service"
  value       = google_cloud_run_v2_service.reasoning_agent.name
}

output "tool_agent_url" {
  description = "URL of the Tool Agent Cloud Run service"
  value       = google_cloud_run_v2_service.tool_agent.uri
  sensitive   = false
}

output "tool_agent_name" {
  description = "Name of the Tool Agent service"
  value       = google_cloud_run_v2_service.tool_agent.name
}

# All agent URLs in a convenient map format
output "agent_service_urls" {
  description = "Map of all agent service URLs for easy reference"
  value = {
    vision    = google_cloud_run_v2_service.vision_agent.uri
    language  = google_cloud_run_v2_service.language_agent.uri
    reasoning = google_cloud_run_v2_service.reasoning_agent.uri
    tool      = google_cloud_run_v2_service.tool_agent.uri
  }
}

# Redis Outputs
output "redis_instance_id" {
  description = "ID of the Cloud Memorystore Redis instance"
  value       = module.redis_cache.id
}

output "redis_host" {
  description = "Host address of the Redis instance for agent state caching"
  value       = module.redis_cache.host
  sensitive   = false
}

output "redis_port" {
  description = "Port of the Redis instance"
  value       = module.redis_cache.port
}

output "redis_connection_name" {
  description = "Connection name for the Redis instance"
  value       = module.redis_cache.connection_name
}

output "redis_auth_string" {
  description = "Authentication string for Redis (sensitive)"
  value       = module.redis_cache.auth_string
  sensitive   = true
}

output "redis_memory_size_gb" {
  description = "Memory size of the Redis instance in GB"
  value       = module.redis_cache.memory_size_gb
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for agent coordination"
  value       = module.agent_pubsub.topic
}

output "pubsub_topic_id" {
  description = "Full ID of the Pub/Sub topic"
  value       = module.agent_pubsub.id
}

output "pubsub_subscriptions" {
  description = "List of Pub/Sub subscriptions created for agent communication"
  value       = module.agent_pubsub.subscription_names
}

# Service Account Outputs
output "cloud_run_service_account_email" {
  description = "Email address of the service account used by Cloud Run services"
  value       = google_service_account.cloud_run_service_account.email
}

output "cloud_run_service_account_name" {
  description = "Name of the service account used by Cloud Run services"
  value       = google_service_account.cloud_run_service_account.name
}

# Artifact Registry Outputs
output "artifact_registry_repository_id" {
  description = "ID of the Artifact Registry repository for agent images"
  value       = google_artifact_registry_repository.agent_images.repository_id
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}"
}

# Monitoring and Logging Outputs
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard for the AI system"
  value       = google_monitoring_dashboard.ai_system_dashboard.id
}

output "log_metric_name" {
  description = "Name of the log-based metric for agent response times"
  value       = google_logging_metric.agent_response_time.name
}

output "alert_policy_name" {
  description = "Name of the alerting policy for high GPU costs"
  value       = google_monitoring_alert_policy.high_gpu_cost_alert.display_name
}

# GPU Configuration Outputs
output "gpu_type" {
  description = "Type of GPU configured for the AI agents"
  value       = var.gpu_type
}

output "gpu_enabled_services" {
  description = "List of Cloud Run services with GPU acceleration enabled"
  value = [
    google_cloud_run_v2_service.vision_agent.name,
    google_cloud_run_v2_service.language_agent.name,
    google_cloud_run_v2_service.reasoning_agent.name
  ]
}

# Scaling Configuration Outputs
output "scaling_configuration" {
  description = "Scaling configuration for all agents"
  value = {
    min_instances      = var.min_instances
    max_instances_gpu  = var.max_instances_gpu
    max_instances_cpu  = var.max_instances_cpu
  }
}

# Cost and Resource Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate, based on minimal usage)"
  value = {
    note = "Actual costs will vary based on usage patterns, scaling, and GPU utilization"
    gpu_services = {
      description = "3 GPU-enabled Cloud Run services"
      base_cost   = "~$50-150/day with minimal usage"
    }
    redis = {
      description = "Cloud Memorystore Redis instance"
      base_cost   = "~$30-100/month depending on tier and size"
    }
    pubsub = {
      description = "Pub/Sub messaging"
      base_cost   = "~$1-10/month based on message volume"
    }
    monitoring = {
      description = "Cloud Monitoring and Logging"
      base_cost   = "~$5-20/month"
    }
  }
}

# Testing and Validation Outputs
output "health_check_urls" {
  description = "Health check URLs for all agent services"
  value = {
    vision    = "${google_cloud_run_v2_service.vision_agent.uri}/health"
    language  = "${google_cloud_run_v2_service.language_agent.uri}/health"
    reasoning = "${google_cloud_run_v2_service.reasoning_agent.uri}/health"
    tool      = "${google_cloud_run_v2_service.tool_agent.uri}/health"
  }
}

# Environment Variables for Client Applications
output "client_environment_variables" {
  description = "Environment variables that client applications should use to connect to the multi-agent system"
  value = {
    REDIS_HOST         = module.redis_cache.host
    REDIS_PORT         = tostring(module.redis_cache.port)
    PUBSUB_TOPIC       = module.agent_pubsub.topic
    PROJECT_ID         = var.project_id
    REGION             = var.region
    VISION_AGENT_URL   = google_cloud_run_v2_service.vision_agent.uri
    LANGUAGE_AGENT_URL = google_cloud_run_v2_service.language_agent.uri
    REASONING_AGENT_URL = google_cloud_run_v2_service.reasoning_agent.uri
    TOOL_AGENT_URL     = google_cloud_run_v2_service.tool_agent.uri
  }
  sensitive = false
}

# Resource Names for Reference
output "resource_names" {
  description = "Names of all created resources for reference and management"
  value = {
    vpc_network        = google_compute_network.agent_network.name
    subnet            = google_compute_subnetwork.agent_subnet.name
    redis_instance    = module.redis_cache.id
    pubsub_topic      = module.agent_pubsub.topic
    artifact_registry = google_artifact_registry_repository.agent_images.repository_id
    service_account   = google_service_account.cloud_run_service_account.name
    services = {
      vision    = google_cloud_run_v2_service.vision_agent.name
      language  = google_cloud_run_v2_service.language_agent.name
      reasoning = google_cloud_run_v2_service.reasoning_agent.name
      tool      = google_cloud_run_v2_service.tool_agent.name
    }
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details for the deployment"
  value = {
    vpc_enabled              = true
    private_ip_google_access = google_compute_subnetwork.agent_subnet.private_ip_google_access
    redis_auth_enabled       = true
    redis_transit_encryption = "SERVER_CLIENT"
    iam_service_account      = google_service_account.cloud_run_service_account.email
  }
}

# Labels Applied to Resources
output "applied_labels" {
  description = "Labels applied to all resources in this deployment"
  value = {
    environment = var.environment
    component   = "multi-agent-ai"
    managed-by  = "terraform"
    project     = var.project_id
  }
}

# Terraform State Information
output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to quickly test the deployed infrastructure"
  value = {
    test_vision_agent = "curl ${google_cloud_run_v2_service.vision_agent.uri}/health"
    test_language_agent = "curl ${google_cloud_run_v2_service.language_agent.uri}/health"
    test_reasoning_agent = "curl ${google_cloud_run_v2_service.reasoning_agent.uri}/health"
    test_tool_agent = "curl ${google_cloud_run_v2_service.tool_agent.uri}/health"
    view_monitoring = "gcloud monitoring dashboards list --filter='displayName:Multi-Agent AI System Dashboard'"
    check_redis = "gcloud redis instances describe ${module.redis_cache.id} --region=${var.region}"
    list_pubsub_subs = "gcloud pubsub subscriptions list --filter='topic:${module.agent_pubsub.topic}'"
  }
}

# Resource Dependencies Information
output "deployment_dependencies" {
  description = "Information about resource dependencies and deployment order"
  value = {
    note = "Resources are deployed in dependency order automatically by Terraform"
    critical_dependencies = [
      "Google Cloud APIs must be enabled first",
      "VPC network and subnet creation",
      "Service account and IAM permissions",
      "Redis instance provisioning",
      "Artifact Registry repository creation",
      "Cloud Run services deployment"
    ]
  }
}