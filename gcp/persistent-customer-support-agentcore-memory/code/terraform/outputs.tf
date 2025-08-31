# Outputs for GCP Persistent AI Customer Support with Agent Engine Memory
# Terraform Infrastructure Configuration

# Project and deployment information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Firestore database information
output "firestore_database_name" {
  description = "Name of the Firestore database for conversation memory"
  value       = google_firestore_database.conversation_memory.name
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.conversation_memory.location_id
}

output "firestore_database_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.conversation_memory.type
}

# Cloud Functions information
output "memory_retrieval_function" {
  description = "Memory retrieval Cloud Function details"
  value = {
    name        = google_cloudfunctions2_function.memory_retrieval.name
    url         = google_cloudfunctions2_function.memory_retrieval.service_config[0].uri
    location    = google_cloudfunctions2_function.memory_retrieval.location
    runtime     = var.memory_retrieval_function_config.runtime
    entry_point = var.memory_retrieval_function_config.entry_point
  }
}

output "ai_chat_function" {
  description = "AI chat Cloud Function details"
  value = {
    name        = google_cloudfunctions2_function.ai_chat.name
    url         = google_cloudfunctions2_function.ai_chat.service_config[0].uri
    location    = google_cloudfunctions2_function.ai_chat.location
    runtime     = var.chat_function_config.runtime
    entry_point = var.chat_function_config.entry_point
  }
}

# Service account information
output "service_account" {
  description = "Service account details for Cloud Functions"
  value = var.create_service_account ? {
    email        = google_service_account.functions_sa[0].email
    display_name = google_service_account.functions_sa[0].display_name
    unique_id    = google_service_account.functions_sa[0].unique_id
  } : null
}

# Storage bucket information
output "function_source_bucket" {
  description = "Cloud Storage bucket for function source code"
  value = {
    name     = google_storage_bucket.function_source.name
    location = google_storage_bucket.function_source.location
    url      = google_storage_bucket.function_source.url
  }
}

# Vertex AI configuration
output "vertex_ai_config" {
  description = "Vertex AI model configuration"
  value = {
    model_name        = var.vertex_ai_config.model_name
    max_output_tokens = var.vertex_ai_config.max_output_tokens
    temperature       = var.vertex_ai_config.temperature
    top_p            = var.vertex_ai_config.top_p
    region           = var.region
  }
}

# VPC Connector information (if enabled)
output "vpc_connector" {
  description = "VPC Connector details (if enabled)"
  value = var.enable_vpc_connector ? {
    name          = google_vpc_access_connector.functions_connector[0].name
    ip_cidr_range = google_vpc_access_connector.functions_connector[0].ip_cidr_range
    network       = google_vpc_access_connector.functions_connector[0].network
    state         = google_vpc_access_connector.functions_connector[0].state
  } : null
}

# Testing endpoints
output "testing_endpoints" {
  description = "Endpoints for testing the AI customer support system"
  value = {
    memory_retrieval_url = google_cloudfunctions2_function.memory_retrieval.service_config[0].uri
    ai_chat_url         = google_cloudfunctions2_function.ai_chat.service_config[0].uri
    test_commands = {
      memory_test = "curl -X POST ${google_cloudfunctions2_function.memory_retrieval.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"customer_id\": \"test-customer-001\"}'"
      chat_test   = "curl -X POST ${google_cloudfunctions2_function.ai_chat.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"customer_id\": \"test-customer-001\", \"message\": \"Hello, I need help with my order\"}'"
    }
  }
}

# Security and IAM information
output "security_configuration" {
  description = "Security and IAM configuration details"
  value = {
    unauthenticated_access_enabled = var.allow_unauthenticated
    service_account_created        = var.create_service_account
    vpc_connector_enabled          = var.enable_vpc_connector
    monitoring_enabled            = var.enable_monitoring
  }
}

# Enabled APIs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = local.required_apis
}

# Resource naming information
output "resource_naming" {
  description = "Information about resource naming convention"
  value = {
    prefix     = var.resource_prefix
    suffix     = random_id.suffix.hex
    pattern    = "${var.resource_prefix}-{resource-type}-${random_id.suffix.hex}"
    labels     = local.common_labels
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Cost optimization settings and recommendations"
  value = {
    memory_function_config = {
      memory_mb       = var.memory_retrieval_function_config.memory_mb
      timeout_seconds = var.memory_retrieval_function_config.timeout_seconds
      min_instances   = var.memory_retrieval_function_config.min_instances
      max_instances   = var.memory_retrieval_function_config.max_instances
    }
    chat_function_config = {
      memory_mb       = var.chat_function_config.memory_mb
      timeout_seconds = var.chat_function_config.timeout_seconds
      min_instances   = var.chat_function_config.min_instances
      max_instances   = var.chat_function_config.max_instances
    }
    estimated_monthly_cost = "Estimated cost: $5-50/month for moderate usage (depends on Vertex AI usage, function invocations, and Firestore operations)"
  }
}

# Firestore index information
output "firestore_indexes" {
  description = "Firestore indexes created for optimal query performance"
  value = {
    conversation_queries = {
      collection = "conversations"
      fields = [
        {
          field_path = "customer_id"
          order      = "ASCENDING"
        },
        {
          field_path = "timestamp"
          order      = "DESCENDING"
        }
      ]
    }
  }
}

# Monitoring and alerting configuration
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration (if enabled)"
  value = var.enable_monitoring ? {
    notification_channels = "email alerts configured"
    alert_policies = [
      {
        name        = "AI Support Function Errors"
        description = "Alerts on high error rates in Cloud Functions"
        threshold   = "5 errors in 5 minutes"
      }
    ]
    dashboard_url = "https://console.cloud.google.com/monitoring/dashboards"
  } : null
}

# Deployment validation commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_apis = "gcloud services list --enabled --project=${var.project_id}"
    check_functions = "gcloud functions list --project=${var.project_id} --region=${var.region}"
    check_firestore = "gcloud firestore databases describe --database=${google_firestore_database.conversation_memory.name} --project=${var.project_id}"
    test_memory_function = "curl -X POST ${google_cloudfunctions2_function.memory_retrieval.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"customer_id\": \"test-123\"}'"
    test_chat_function = "curl -X POST ${google_cloudfunctions2_function.ai_chat.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"customer_id\": \"test-123\", \"message\": \"Hello\"}'"
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "gcloud functions delete ${google_cloudfunctions2_function.memory_retrieval.name} --region=${var.region} --project=${var.project_id}",
      "gcloud functions delete ${google_cloudfunctions2_function.ai_chat.name} --region=${var.region} --project=${var.project_id}",
      "gcloud firestore databases delete --database=${google_firestore_database.conversation_memory.name} --project=${var.project_id}",
      "gsutil rm -r gs://${google_storage_bucket.function_source.name}"
    ]
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    test_deployment = "Use the provided test commands to validate the AI customer support system"
    create_web_interface = "Create a web interface using the provided function URLs"
    monitor_usage = "Monitor function usage and costs in the Cloud Console"
    enhance_security = "Implement authentication and remove unauthenticated access for production"
    add_features = [
      "Implement sentiment analysis with Cloud Natural Language API",
      "Add multi-language support with Cloud Translation API",
      "Create analytics dashboard with BigQuery and Looker",
      "Integrate with existing CRM systems"
    ]
    production_considerations = [
      "Enable VPC connector for network security",
      "Implement proper authentication and authorization",
      "Set up comprehensive monitoring and alerting",
      "Configure backup and disaster recovery",
      "Implement data encryption at rest and in transit"
    ]
  }
}