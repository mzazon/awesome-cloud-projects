# =============================================================================
# MULTI-AGENT CUSTOMER SERVICE WITH AGENT2AGENT AND CONTACT CENTER AI
# =============================================================================
# This Terraform configuration creates a complete multi-agent customer service
# system using Google Cloud Contact Center AI Platform, Vertex AI, Cloud Functions,
# and Firestore for intelligent agent collaboration following A2A protocol principles.

# =============================================================================
# LOCAL VALUES AND RESOURCE NAMING
# =============================================================================

locals {
  # Generate consistent resource naming with randomization
  name_prefix = var.name_prefix != "" ? var.name_prefix : "agent-${random_id.suffix.hex}"
  
  # Common labels for resource organization and cost tracking
  common_labels = merge(var.labels, {
    project     = "multi-agent-customer-service"
    environment = var.environment
    managed_by  = "terraform"
    component   = "ai-customer-service"
  })

  # Function source code paths (relative to module root)
  function_sources = {
    router    = "${path.module}/functions/agent-router"
    broker    = "${path.module}/functions/message-broker"
    billing   = "${path.module}/functions/billing-agent"
    technical = "${path.module}/functions/technical-agent"
    sales     = "${path.module}/functions/sales-agent"
  }

  # Knowledge base initial data for agent specializations
  knowledge_base_data = {
    billing = {
      domain          = "billing"
      capabilities    = ["payments", "invoices", "refunds", "subscriptions"]
      expertise_level = "expert"
    }
    technical = {
      domain          = "technical"
      capabilities    = ["troubleshooting", "installations", "configurations", "diagnostics"]
      expertise_level = "expert"
    }
    sales = {
      domain          = "sales"
      capabilities    = ["product_info", "pricing", "demos", "upgrades"]
      expertise_level = "expert"
    }
  }
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# =============================================================================
# PROJECT CONFIGURATION AND API ENABLEMENT
# =============================================================================

# Enable required Google Cloud APIs for multi-agent architecture
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",           # Vertex AI for agent intelligence
    "cloudfunctions.googleapis.com",       # Cloud Functions for agent services
    "firestore.googleapis.com",            # Firestore for knowledge base
    "bigquery.googleapis.com",             # BigQuery for analytics
    "dialogflow.googleapis.com",           # Dialogflow for conversation management
    "contactcenteraiplatform.googleapis.com", # Contact Center AI Platform
    "cloudbuild.googleapis.com",           # Cloud Build for function deployment
    "storage.googleapis.com",              # Cloud Storage for artifacts
    "pubsub.googleapis.com",               # Pub/Sub for inter-agent messaging
    "cloudresourcemanager.googleapis.com", # Resource management
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# =============================================================================
# FIRESTORE DATABASE FOR KNOWLEDGE BASE
# =============================================================================

# Firestore database for centralized knowledge base and conversation storage
resource "google_firestore_database" "knowledge_base" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # Ensure API is enabled before creating database
  depends_on = [
    google_project_service.required_apis["firestore.googleapis.com"]
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Knowledge base documents for agent capabilities and expertise
resource "google_firestore_document" "agent_knowledge" {
  for_each = local.knowledge_base_data

  project     = var.project_id
  collection  = "knowledge"
  document_id = each.key
  fields      = jsonencode(each.value)

  depends_on = [google_firestore_database.knowledge_base]
}

# =============================================================================
# VERTEX AI INFRASTRUCTURE
# =============================================================================

# Vertex AI dataset for agent training and model artifacts
resource "google_vertex_ai_dataset" "agent_dataset" {
  project      = var.project_id
  region       = var.region
  display_name = "multi-agent-customer-service"
  
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/text_1.0.0.yaml"

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["aiplatform.googleapis.com"]
  ]
}

# =============================================================================
# CLOUD STORAGE FOR MODEL ARTIFACTS
# =============================================================================

# Storage bucket for model artifacts and training data
resource "google_storage_bucket" "agent_models" {
  project  = var.project_id
  name     = "${var.project_id}-${local.name_prefix}-models"
  location = var.region

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for model artifact management
  versioning {
    enabled = true
  }

  # Security and access control
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["storage.googleapis.com"]
  ]
}

# =============================================================================
# BIGQUERY DATASET FOR ANALYTICS AND LOGGING
# =============================================================================

# BigQuery dataset for conversation logs and analytics
resource "google_bigquery_dataset" "conversation_analytics" {
  project    = var.project_id
  dataset_id = replace("${local.name_prefix}_analytics", "-", "_")
  location   = var.region

  friendly_name   = "Multi-Agent Customer Service Analytics"
  description     = "Dataset for conversation logs, agent performance metrics, and customer service analytics"
  default_table_expiration_ms = 2592000000 # 30 days

  # Access control for analytics team
  access {
    role          = "OWNER"
    user_by_email = var.analytics_admin_email
  }

  access {
    role   = "READER"
    domain = var.organization_domain
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["bigquery.googleapis.com"]
  ]
}

# Conversation logs table schema
resource "google_bigquery_table" "conversation_logs" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.conversation_analytics.dataset_id
  table_id   = "conversation_logs"

  description = "Detailed conversation logs for agent performance analysis and optimization"

  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  clustering = ["agent_type", "session_id"]

  schema = jsonencode([
    {
      name = "session_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique session identifier for conversation tracking"
    },
    {
      name = "agent_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of agent handling the conversation (billing, technical, sales)"
    },
    {
      name = "customer_message"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer inquiry message"
    },
    {
      name = "agent_response"
      type = "STRING"
      mode = "NULLABLE"
      description = "Agent response to customer inquiry"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Routing confidence score for analytics"
    },
    {
      name = "handoff_reason"
      type = "STRING"
      mode = "NULLABLE"
      description = "Reason for agent handoff if applicable"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Conversation timestamp for time-based analysis"
    }
  ])

  labels = local.common_labels
}

# =============================================================================
# CLOUD FUNCTIONS FOR AGENT SERVICES
# =============================================================================

# Service account for Cloud Functions with least privilege access
resource "google_service_account" "function_service_account" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-functions"
  display_name = "Multi-Agent Functions Service Account"
  description  = "Service account for Cloud Functions with minimal required permissions"
}

# IAM permissions for Firestore access
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# IAM permissions for BigQuery data editor (for logging)
resource "google_project_iam_member" "function_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# IAM permissions for Vertex AI user
resource "google_service_account_iam_member" "function_vertex_ai_user" {
  service_account_id = google_service_account.function_service_account.name
  role               = "roles/aiplatform.user"
  member             = "serviceAccount:${google_service_account.function_service_account.email}"
}

# ZIP archive for Agent Router Function
data "archive_file" "agent_router_zip" {
  type        = "zip"
  output_path = "${path.module}/temp/agent-router.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/agent_router.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements_router.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket object for Agent Router Function
resource "google_storage_bucket_object" "agent_router_source" {
  name   = "functions/agent-router-${data.archive_file.agent_router_zip.output_md5}.zip"
  bucket = google_storage_bucket.agent_models.name
  source = data.archive_file.agent_router_zip.output_path

  depends_on = [data.archive_file.agent_router_zip]
}

# Agent Router Cloud Function - Central orchestrator for intelligent routing
resource "google_cloudfunctions_function" "agent_router" {
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-router"

  description = "Intelligent agent router analyzing customer inquiries and routing to specialized agents"
  runtime     = "python311"
  available_memory_mb = 256
  timeout             = 60
  entry_point         = "route_agent"
  service_account_email = google_service_account.function_service_account.email

  source_archive_bucket = google_storage_bucket.agent_models.name
  source_archive_object = google_storage_bucket_object.agent_router_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
    DATASET_ID = google_bigquery_dataset.conversation_analytics.dataset_id
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_firestore_database.knowledge_base
  ]
}

# ZIP archive for Message Broker Function
data "archive_file" "message_broker_zip" {
  type        = "zip"
  output_path = "${path.module}/temp/message-broker.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/message_broker.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements_broker.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket object for Message Broker Function
resource "google_storage_bucket_object" "message_broker_source" {
  name   = "functions/message-broker-${data.archive_file.message_broker_zip.output_md5}.zip"
  bucket = google_storage_bucket.agent_models.name
  source = data.archive_file.message_broker_zip.output_path

  depends_on = [data.archive_file.message_broker_zip]
}

# Message Broker Cloud Function - A2A protocol implementation for agent communication
resource "google_cloudfunctions_function" "message_broker" {
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-broker"

  description = "Agent2Agent protocol message broker for seamless inter-agent communication"
  runtime     = "python311"
  available_memory_mb = 512
  timeout             = 120
  entry_point         = "broker_message"
  service_account_email = google_service_account.function_service_account.email

  source_archive_bucket = google_storage_bucket.agent_models.name
  source_archive_object = google_storage_bucket_object.message_broker_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
    DATASET_ID = google_bigquery_dataset.conversation_analytics.dataset_id
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_firestore_database.knowledge_base
  ]
}

# ZIP archives and Cloud Functions for specialized agents
locals {
  agent_types = ["billing", "technical", "sales"]
}

# ZIP archives for specialized agent functions
data "archive_file" "specialized_agent_zip" {
  for_each = toset(local.agent_types)
  
  type        = "zip"
  output_path = "${path.module}/temp/${each.value}-agent.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/specialized_agent.py", {
      agent_type = each.value
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements_agent.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket objects for specialized agent functions
resource "google_storage_bucket_object" "specialized_agent_source" {
  for_each = toset(local.agent_types)
  
  name   = "functions/${each.value}-agent-${data.archive_file.specialized_agent_zip[each.value].output_md5}.zip"
  bucket = google_storage_bucket.agent_models.name
  source = data.archive_file.specialized_agent_zip[each.value].output_path

  depends_on = [data.archive_file.specialized_agent_zip]
}

# Specialized Agent Cloud Functions - Domain-specific customer service agents
resource "google_cloudfunctions_function" "specialized_agents" {
  for_each = toset(local.agent_types)
  
  project = var.project_id
  region  = var.region
  name    = "${local.name_prefix}-${each.value}"

  description = "Specialized ${each.value} agent with domain expertise and A2A communication"
  runtime     = "python311"
  available_memory_mb = 256
  timeout             = 60
  entry_point         = "${each.value}_agent"
  service_account_email = google_service_account.function_service_account.email

  source_archive_bucket = google_storage_bucket.agent_models.name
  source_archive_object = google_storage_bucket_object.specialized_agent_source[each.value].name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    PROJECT_ID  = var.project_id
    REGION      = var.region
    AGENT_TYPE  = each.value
    DATASET_ID  = google_bigquery_dataset.conversation_analytics.dataset_id
  }

  labels = merge(local.common_labels, {
    agent_type = each.value
  })

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_firestore_database.knowledge_base
  ]
}

# =============================================================================
# CONTACT CENTER AI PLATFORM CONFIGURATION
# =============================================================================

# Store CCAI configuration in Firestore for reference
resource "google_firestore_document" "ccai_config" {
  project     = var.project_id
  collection  = "configuration"
  document_id = "ccai-platform"

  fields = jsonencode({
    display_name             = "Multi-Agent Customer Service"
    default_language_code    = "en"
    supported_language_codes = ["en"]
    time_zone               = var.time_zone
    description             = "AI-powered customer service with specialized agent collaboration"
    features = {
      inbound_call  = true
      outbound_call = false
      chat          = true
      email         = true
    }
    agent_config = {
      virtual_agent = {
        enabled           = true
        fallback_to_human = true
      }
      agent_assist = {
        enabled        = true
        knowledge_base = true
      }
    }
  })

  depends_on = [google_firestore_database.knowledge_base]
}

# Store integration endpoints for CCAI platform reference
resource "google_firestore_document" "integration_endpoints" {
  project     = var.project_id
  collection  = "integration"
  document_id = "endpoints"

  fields = jsonencode({
    router_url      = google_cloudfunctions_function.agent_router.https_trigger_url
    broker_url      = google_cloudfunctions_function.message_broker.https_trigger_url
    billing_url     = google_cloudfunctions_function.specialized_agents["billing"].https_trigger_url
    technical_url   = google_cloudfunctions_function.specialized_agents["technical"].https_trigger_url
    sales_url       = google_cloudfunctions_function.specialized_agents["sales"].https_trigger_url
    configured_date = timestamp()
  })

  depends_on = [
    google_firestore_database.knowledge_base,
    google_cloudfunctions_function.agent_router,
    google_cloudfunctions_function.message_broker,
    google_cloudfunctions_function.specialized_agents
  ]
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Log sink for function logs to BigQuery
resource "google_logging_project_sink" "function_logs_sink" {
  name = "${local.name_prefix}-function-logs"

  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.conversation_analytics.dataset_id}"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"^${local.name_prefix}-(router|broker|billing|technical|sales)$"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [google_bigquery_dataset.conversation_analytics]
}

# Grant BigQuery Data Editor role to log sink service account
resource "google_project_iam_member" "log_sink_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.function_logs_sink.writer_identity
}

# =============================================================================
# SECURITY AND ACCESS CONTROL
# =============================================================================

# IAM policy for secure function invocation
resource "google_cloudfunctions_function_iam_member" "invoker" {
  for_each = {
    router    = google_cloudfunctions_function.agent_router.name
    broker    = google_cloudfunctions_function.message_broker.name
    billing   = google_cloudfunctions_function.specialized_agents["billing"].name
    technical = google_cloudfunctions_function.specialized_agents["technical"].name
    sales     = google_cloudfunctions_function.specialized_agents["sales"].name
  }

  project        = var.project_id
  region         = var.region
  cloud_function = each.value
  role           = "roles/cloudfunctions.invoker"
  member         = var.allow_public_access ? "allUsers" : "serviceAccount:${google_service_account.function_service_account.email}"
}