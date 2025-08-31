# =============================================================================
# TERRAFORM OUTPUTS FOR MULTI-AGENT CUSTOMER SERVICE
# =============================================================================
# Output values for integration, testing, and operational management
# of the multi-agent customer service system

# =============================================================================
# PROJECT AND RESOURCE INFORMATION
# =============================================================================

output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "name_prefix" {
  description = "Resource name prefix used for all components"
  value       = local.name_prefix
}

output "environment" {
  description = "Environment designation for the deployment"
  value       = var.environment
}

# =============================================================================
# CLOUD FUNCTIONS ENDPOINTS
# =============================================================================

output "agent_router_url" {
  description = "HTTPS trigger URL for the Agent Router function"
  value       = google_cloudfunctions_function.agent_router.https_trigger_url
  sensitive   = false
}

output "message_broker_url" {
  description = "HTTPS trigger URL for the Message Broker function"
  value       = google_cloudfunctions_function.message_broker.https_trigger_url
  sensitive   = false
}

output "billing_agent_url" {
  description = "HTTPS trigger URL for the Billing Agent function"
  value       = google_cloudfunctions_function.specialized_agents["billing"].https_trigger_url
  sensitive   = false
}

output "technical_agent_url" {
  description = "HTTPS trigger URL for the Technical Agent function"
  value       = google_cloudfunctions_function.specialized_agents["technical"].https_trigger_url
  sensitive   = false
}

output "sales_agent_url" {
  description = "HTTPS trigger URL for the Sales Agent function"
  value       = google_cloudfunctions_function.specialized_agents["sales"].https_trigger_url
  sensitive   = false
}

output "all_function_urls" {
  description = "Map of all Cloud Function URLs for easy reference"
  value = {
    router    = google_cloudfunctions_function.agent_router.https_trigger_url
    broker    = google_cloudfunctions_function.message_broker.https_trigger_url
    billing   = google_cloudfunctions_function.specialized_agents["billing"].https_trigger_url
    technical = google_cloudfunctions_function.specialized_agents["technical"].https_trigger_url
    sales     = google_cloudfunctions_function.specialized_agents["sales"].https_trigger_url
  }
}

# =============================================================================
# FIRESTORE DATABASE INFORMATION
# =============================================================================

output "firestore_database_name" {
  description = "Firestore database name for knowledge base and conversation storage"
  value       = google_firestore_database.knowledge_base.name
}

output "firestore_location" {
  description = "Firestore database location"
  value       = google_firestore_database.knowledge_base.location_id
}

output "knowledge_base_collections" {
  description = "Firestore collections for agent knowledge base"
  value = {
    knowledge     = "knowledge"
    conversations = "conversations"
    routing_logs  = "routing_logs"
    agent_interactions = "agent_interactions"
    integration   = "integration"
    configuration = "configuration"
  }
}

# =============================================================================
# VERTEX AI RESOURCES
# =============================================================================

output "vertex_ai_dataset_id" {
  description = "Vertex AI dataset ID for agent training data"
  value       = google_vertex_ai_dataset.agent_dataset.name
}

output "vertex_ai_dataset_display_name" {
  description = "Vertex AI dataset display name"
  value       = google_vertex_ai_dataset.agent_dataset.display_name
}

output "model_storage_bucket" {
  description = "Cloud Storage bucket for model artifacts and training data"
  value       = google_storage_bucket.agent_models.name
}

output "model_storage_bucket_url" {
  description = "Cloud Storage bucket URL for model artifacts"
  value       = google_storage_bucket.agent_models.url
}

# =============================================================================
# BIGQUERY ANALYTICS RESOURCES
# =============================================================================

output "analytics_dataset_id" {
  description = "BigQuery dataset ID for conversation analytics"
  value       = google_bigquery_dataset.conversation_analytics.dataset_id
}

output "analytics_dataset_location" {
  description = "BigQuery dataset location"
  value       = google_bigquery_dataset.conversation_analytics.location
}

output "conversation_logs_table" {
  description = "BigQuery table for conversation logs"
  value       = "${google_bigquery_dataset.conversation_analytics.dataset_id}.${google_bigquery_table.conversation_logs.table_id}"
}

output "bigquery_analytics_url" {
  description = "BigQuery console URL for analytics dataset"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.conversation_analytics.dataset_id}!3s${google_bigquery_table.conversation_logs.table_id}"
}

# =============================================================================
# SERVICE ACCOUNT AND SECURITY
# =============================================================================

output "function_service_account_email" {
  description = "Service account email used by Cloud Functions"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_id" {
  description = "Service account ID used by Cloud Functions"
  value       = google_service_account.function_service_account.account_id
}

output "log_sink_writer_identity" {
  description = "Log sink writer identity for BigQuery integration"
  value       = google_logging_project_sink.function_logs_sink.writer_identity
  sensitive   = true
}

# =============================================================================
# CONTACT CENTER AI PLATFORM CONFIGURATION
# =============================================================================

output "ccai_configuration" {
  description = "Contact Center AI Platform configuration reference"
  value = {
    display_name          = var.ccai_display_name
    supported_languages   = var.supported_languages
    time_zone            = var.time_zone
    voice_support        = var.enable_voice_support
    chat_support         = var.enable_chat_support
    email_support        = var.enable_email_support
    firestore_config_doc = "configuration/ccai-platform"
  }
}

output "integration_endpoints_doc" {
  description = "Firestore document path containing integration endpoints"
  value       = "integration/endpoints"
}

# =============================================================================
# TESTING AND VALIDATION INFORMATION
# =============================================================================

output "test_commands" {
  description = "Commands for testing the multi-agent system"
  value = {
    test_router = "curl -X POST ${google_cloudfunctions_function.agent_router.https_trigger_url} -H 'Content-Type: application/json' -d '{\"message\":\"I need help with my monthly invoice\",\"session_id\":\"test-001\"}'"
    test_broker = "curl -X POST ${google_cloudfunctions_function.message_broker.https_trigger_url} -H 'Content-Type: application/json' -d '{\"source_agent\":\"billing\",\"target_agent\":\"technical\",\"message\":\"Customer needs technical help\",\"session_id\":\"test-001\"}'"
    test_billing = "curl -X POST ${google_cloudfunctions_function.specialized_agents["billing"].https_trigger_url} -H 'Content-Type: application/json' -d '{\"message\":\"I want a refund\",\"session_id\":\"test-002\"}'"
  }
}

output "firestore_test_commands" {
  description = "Commands for validating Firestore knowledge base"
  value = {
    list_knowledge    = "gcloud firestore documents list knowledge --project=${var.project_id}"
    list_routing_logs = "gcloud firestore documents list routing_logs --project=${var.project_id} --limit=5"
    check_endpoints   = "gcloud firestore documents describe integration/endpoints --project=${var.project_id}"
  }
}

# =============================================================================
# MONITORING AND OPERATIONS
# =============================================================================

output "cloud_console_urls" {
  description = "Google Cloud Console URLs for monitoring and operations"
  value = {
    functions_dashboard = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
    firestore_console  = "https://console.cloud.google.com/firestore/data?project=${var.project_id}"
    vertex_ai_console  = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    bigquery_console   = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    logging_console    = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    monitoring_console = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

output "log_queries" {
  description = "Useful log queries for monitoring the system"
  value = {
    function_errors = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"^${local.name_prefix}\" AND severity>=ERROR"
    routing_decisions = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.name_prefix}-router\" AND textPayload:\"routing_decision\""
    agent_handoffs = "resource.type=\"cloud_function\" AND textPayload:\"handoff\""
    performance_metrics = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"^${local.name_prefix}\" AND jsonPayload.execution_time_ms>1000"
  }
}

# =============================================================================
# COST INFORMATION
# =============================================================================

output "cost_tracking_labels" {
  description = "Labels for cost tracking and analysis"
  value = local.common_labels
}

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for different usage levels (USD)"
  value = {
    light_usage = {
      description = "< 1,000 requests/month"
      estimate    = "$5-15"
      breakdown = {
        cloud_functions = "$1-5"
        firestore      = "$1-3"
        vertex_ai      = "$1-5"
        bigquery       = "$1-2"
      }
    }
    moderate_usage = {
      description = "1,000-10,000 requests/month"
      estimate    = "$15-50"
      breakdown = {
        cloud_functions = "$5-20"
        firestore      = "$3-10"
        vertex_ai      = "$5-15"
        bigquery       = "$2-5"
      }
    }
    heavy_usage = {
      description = "> 10,000 requests/month"
      estimate    = "$50-200+"
      breakdown = {
        cloud_functions = "$20-100+"
        firestore      = "$10-30"
        vertex_ai      = "$15-50+"
        bigquery       = "$5-20"
      }
    }
  }
}

# =============================================================================
# AGENT CONFIGURATION REFERENCE
# =============================================================================

output "agent_specializations" {
  description = "Agent specialization configuration for reference"
  value = {
    for agent_type, config in local.knowledge_base_data : agent_type => {
      domain       = config.domain
      capabilities = config.capabilities
      function_url = google_cloudfunctions_function.specialized_agents[agent_type].https_trigger_url
    }
  }
}

output "routing_configuration" {
  description = "Agent routing configuration and keywords"
  value = var.routing_keywords
}

# =============================================================================
# INTEGRATION INFORMATION
# =============================================================================

output "api_integration_guide" {
  description = "Integration guide for external systems"
  value = {
    description = "To integrate with the multi-agent system, use the following endpoints:"
    primary_endpoint = google_cloudfunctions_function.agent_router.https_trigger_url
    request_format = {
      method      = "POST"
      content_type = "application/json"
      body_schema = {
        message    = "string (required) - Customer inquiry message"
        session_id = "string (required) - Unique session identifier"
      }
    }
    response_format = {
      agent_type  = "string - Selected agent type (billing, technical, sales)"
      confidence  = "number - Routing confidence score (0.0-1.0)"
      reasoning   = "string - Explanation for agent selection"
      session_id  = "string - Echo of session identifier"
    }
    webhook_endpoints = {
      for agent_type in local.agent_types : agent_type => google_cloudfunctions_function.specialized_agents[agent_type].https_trigger_url
    }
  }
}

output "a2a_protocol_info" {
  description = "Agent2Agent protocol information for inter-agent communication"
  value = {
    broker_endpoint = google_cloudfunctions_function.message_broker.https_trigger_url
    protocol_version = "1.0"
    message_format = {
      source_agent   = "string - Source agent identifier"
      target_agent   = "string - Target agent identifier"
      message        = "string - Message content for handoff"
      session_id     = "string - Session identifier"
      handoff_reason = "string - Reason for agent handoff"
    }
    supported_agents = local.agent_types
  }
}

# =============================================================================
# OPERATIONAL PROCEDURES
# =============================================================================

output "operational_procedures" {
  description = "Key operational procedures and maintenance commands"
  value = {
    backup_firestore = "gcloud firestore export gs://${google_storage_bucket.agent_models.name}/backups/$(date +%Y%m%d-%H%M%S) --project=${var.project_id}"
    view_function_logs = "gcloud functions logs read ${local.name_prefix}-router --region=${var.region} --project=${var.project_id}"
    scale_functions = "gcloud functions deploy FUNCTION_NAME --max-instances=NUMBER --project=${var.project_id} --region=${var.region}"
    monitor_costs = "gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID"
  }
}

output "troubleshooting_guide" {
  description = "Common troubleshooting steps and diagnostics"
  value = {
    check_api_status = "gcloud services list --enabled --project=${var.project_id}"
    test_firestore = "gcloud firestore documents list knowledge --project=${var.project_id}"
    check_function_health = "gcloud functions describe ${local.name_prefix}-router --region=${var.region} --project=${var.project_id}"
    view_error_logs = "gcloud logging read 'resource.type=\"cloud_function\" AND severity>=ERROR' --project=${var.project_id} --limit=10"
  }
}

# =============================================================================
# SECURITY AND COMPLIANCE
# =============================================================================

output "security_information" {
  description = "Security configuration and compliance information"
  value = {
    service_account        = google_service_account.function_service_account.email
    public_access_enabled  = var.allow_public_access
    encryption_at_rest     = "Google Cloud default encryption (AES-256)"
    encryption_in_transit  = "TLS 1.2+ for HTTPS endpoints"
    data_location         = var.region
    compliance_features = {
      audit_logging     = "Cloud Audit Logs enabled"
      data_retention   = "${var.data_retention_days} days"
      access_control   = "IAM-based with least privilege"
    }
  }
}

output "data_governance" {
  description = "Data governance and privacy information"
  value = {
    data_types = {
      customer_messages    = "Stored in Firestore with server-side encryption"
      conversation_logs   = "Stored in BigQuery with automatic expiration"
      agent_interactions  = "Logged for analytics and optimization"
      routing_decisions   = "Tracked for system improvement"
    }
    retention_policies = {
      firestore_data = "Manual cleanup required"
      bigquery_data  = "${var.data_retention_days} days automatic expiration"
      function_logs  = "30 days default retention"
      storage_objects = "${var.storage_lifecycle_days} days lifecycle policy"
    }
    privacy_controls = {
      pii_handling      = "No automatic PII detection - implement as needed"
      data_anonymization = "Implement session-based anonymization"
      right_to_deletion = "Manual process via Firestore document deletion"
    }
  }
}