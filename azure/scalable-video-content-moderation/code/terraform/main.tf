# Main Terraform configuration for Azure Video Content Moderation Solution
# This configuration deploys a complete intelligent video content moderation pipeline
# using Azure AI Vision, Event Hubs, Stream Analytics, and Logic Apps

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  suffix = random_string.suffix.result
  
  # Effective resource group name - use provided name or generate one
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.suffix}"
  
  # Common resource names with consistent naming convention
  ai_vision_name       = "aivision-${var.project_name}-${local.suffix}"
  eventhub_namespace   = "eh-${var.project_name}-${local.suffix}"
  eventhub_name        = "video-frames"
  storage_account_name = "st${var.project_name}${local.suffix}"
  stream_analytics_job = "sa-${var.project_name}-${local.suffix}"
  logic_app_name       = "la-${var.project_name}-${local.suffix}"
  log_analytics_name   = "log-${var.project_name}-${local.suffix}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    created_by  = "terraform"
    created_on  = timestamp()
  })
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Resource Group - Container for all video moderation resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace - Centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Azure AI Vision Service - Core content moderation and image analysis
resource "azurerm_cognitive_account" "ai_vision" {
  name                = local.ai_vision_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ComputerVision"
  sku_name            = var.ai_vision_sku
  
  # Enable custom subdomain for advanced features
  custom_question_answering_search_service_id = null
  
  # Network access configuration
  network_acls {
    default_action = "Allow"
    
    # In production, restrict to specific IPs or virtual networks
    ip_rules       = []
    virtual_network_rules {
      subnet_id = null
    }
  }
  
  tags = merge(local.common_tags, {
    service = "ai-vision"
    purpose = "content-moderation"
  })
}

# Event Hubs Namespace - High-throughput event streaming platform
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.eventhub_namespace
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  sku                      = var.eventhub_sku
  capacity                 = var.eventhub_capacity
  auto_inflate_enabled     = var.enable_auto_inflate
  maximum_throughput_units = var.enable_auto_inflate ? var.maximum_throughput_units : null
  
  # Network security configuration
  network_rulesets {
    default_action                 = "Allow"
    public_network_access_enabled  = true
    trusted_service_access_enabled = true
    
    # Define IP rules for restricted access (empty for demo)
    ip_rule = []
    
    # Define virtual network rules (empty for demo)
    virtual_network_rule = []
  }
  
  tags = merge(local.common_tags, {
    service = "event-hubs"
    purpose = "video-frame-streaming"
  })
}

# Event Hub - Specific hub for video frame events
resource "azurerm_eventhub" "video_frames" {
  name                = local.eventhub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
  
  # Enable capture to storage for audit and replay scenarios
  capture_description {
    enabled  = false  # Disabled for demo, enable for production archival
    encoding = "Avro"
    
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "eventhub-archive"
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

# Event Hub Authorization Rule - Access credentials for applications
resource "azurerm_eventhub_authorization_rule" "main" {
  name                = "video-moderation-access"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.video_frames.name
  resource_group_name = azurerm_resource_group.main.name
  
  # Permissions for Stream Analytics to read events
  listen = true
  send   = true
  manage = false
}

# Storage Account - Persistent storage for moderation results and artifacts
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  
  # Advanced threat protection
  network_rules {
    default_action = "Allow"
    
    # Production environments should restrict access
    ip_rules   = []
    bypass     = ["AzureServices"]
  }
  
  # Blob properties for lifecycle management
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "PUT", "POST"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    delete_retention_policy {
      days = 7
    }
    
    versioning_enabled = false
    
    change_feed_enabled = false
  }
  
  tags = merge(local.common_tags, {
    service = "storage"
    purpose = "moderation-results"
  })
}

# Storage Container - Container for moderation results
resource "azurerm_storage_container" "moderation_results" {
  name                  = "moderation-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Container - Container for Event Hub archive (if capture enabled)
resource "azurerm_storage_container" "eventhub_archive" {
  name                  = "eventhub-archive"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Stream Analytics Job - Real-time event processing and AI coordination
resource "azurerm_stream_analytics_job" "main" {
  name                                     = local.stream_analytics_job
  resource_group_name                      = azurerm_resource_group.main.name
  location                                 = azurerm_resource_group.main.location
  compatibility_level                      = "1.2"
  data_locale                             = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy              = "Adjust"
  output_error_policy                     = "Stop"
  streaming_units                         = var.stream_analytics_streaming_units
  
  # Job configuration for transformation query
  transformation_query = templatefile("${path.module}/stream_analytics_query.sql", {
    adult_block_threshold  = var.content_moderation_thresholds.adult_block_threshold
    adult_review_threshold = var.content_moderation_thresholds.adult_review_threshold
    racy_block_threshold   = var.content_moderation_thresholds.racy_block_threshold
    racy_review_threshold  = var.content_moderation_thresholds.racy_review_threshold
  })
  
  tags = merge(local.common_tags, {
    service = "stream-analytics"
    purpose = "video-frame-processing"
  })
  
  depends_on = [
    azurerm_eventhub.video_frames,
    azurerm_storage_account.main
  ]
}

# Stream Analytics Input - Event Hubs input for video frame events
resource "azurerm_stream_analytics_stream_input_eventhub" "video_frames" {
  name                         = "VideoFrameInput"
  stream_analytics_job_name    = azurerm_stream_analytics_job.main.name
  resource_group_name          = azurerm_resource_group.main.name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = azurerm_eventhub.video_frames.name
  servicebus_namespace         = azurerm_eventhub_namespace.main.name
  shared_access_policy_key     = azurerm_eventhub_authorization_rule.main.primary_key
  shared_access_policy_name    = azurerm_eventhub_authorization_rule.main.name
  
  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Stream Analytics Output - Blob storage output for moderation results
resource "azurerm_stream_analytics_output_blob" "moderation_results" {
  name                      = "ModerationOutput"
  stream_analytics_job_name = azurerm_stream_analytics_job.main.name
  resource_group_name       = azurerm_resource_group.main.name
  storage_account_name      = azurerm_storage_account.main.name
  storage_account_key       = azurerm_storage_account.main.primary_access_key
  storage_container_name    = azurerm_storage_container.moderation_results.name
  path_pattern             = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"
  date_format              = "yyyy/MM/dd"
  time_format              = "HH"
  
  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# Logic App - Automated response workflows for content moderation events
resource "azurerm_logic_app_workflow" "main" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Workflow definition for content moderation response
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"
  
  tags = merge(local.common_tags, {
    service = "logic-apps"
    purpose = "moderation-response"
  })
}

# Diagnostic Settings for AI Vision Service
resource "azurerm_monitor_diagnostic_setting" "ai_vision" {
  count = var.enable_monitoring ? 1 : 0
  
  name                       = "ai-vision-diagnostics"
  target_resource_id         = azurerm_cognitive_account.ai_vision.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Event Hubs Namespace
resource "azurerm_monitor_diagnostic_setting" "eventhub" {
  count = var.enable_monitoring ? 1 : 0
  
  name                       = "eventhub-diagnostics"
  target_resource_id         = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "ArchiveLogs"
  }
  
  enabled_log {
    category = "OperationalLogs"
  }
  
  enabled_log {
    category = "AutoScaleLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for Stream Analytics Job
resource "azurerm_monitor_diagnostic_setting" "stream_analytics" {
  count = var.enable_monitoring ? 1 : 0
  
  name                       = "stream-analytics-diagnostics"
  target_resource_id         = azurerm_stream_analytics_job.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  enabled_log {
    category = "Execution"
  }
  
  enabled_log {
    category = "Authoring"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Application Insights for Logic App monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0
  
  name                = "ai-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  
  tags = merge(local.common_tags, {
    service = "application-insights"
    purpose = "logic-app-monitoring"
  })
}