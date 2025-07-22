# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  suffix = random_id.suffix.hex
  
  # Resource names with consistent naming convention
  resource_group_name           = "rg-${var.project_name}-${var.environment}-${local.suffix}"
  content_safety_name          = "cs-${var.project_name}-${var.environment}-${local.suffix}"
  service_bus_namespace_name   = "sb-${var.project_name}-${var.environment}-${local.suffix}"
  storage_account_name         = "st${var.project_name}${var.environment}${local.suffix}"
  container_env_name           = "cae-${var.project_name}-${var.environment}-${local.suffix}"
  container_job_name           = "job-content-processor-${var.environment}"
  log_analytics_workspace_name = "law-${var.project_name}-${var.environment}-${local.suffix}"
  action_group_name            = "ag-${var.project_name}-${var.environment}"
  
  # Computed values
  message_ttl = "PT${var.message_ttl_hours}H"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Suffix      = local.suffix
  })
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure AI Content Safety Service
resource "azurerm_cognitive_account" "content_safety" {
  name                = local.content_safety_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "ContentSafety"
  sku_name            = var.content_safety_sku
  tags                = local.common_tags

  # Enable managed identity for secure access
  identity {
    type = "SystemAssigned"
  }

  # Disable local authentication to enforce managed identity
  local_auth_enabled = false
}

# Service Bus Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                = local.service_bus_namespace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.service_bus_sku
  tags                = local.common_tags

  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }
}

# Service Bus Queue for content processing
resource "azurerm_servicebus_queue" "content_queue" {
  name         = "content-queue"
  namespace_id = azurerm_servicebus_namespace.main.id

  # Queue configuration
  max_size_in_megabytes = var.content_queue_max_size
  default_message_ttl   = local.message_ttl
  
  # Enable dead lettering for failed messages
  dead_lettering_on_message_expiration = true
  max_delivery_count                   = 10
  
  # Enable duplicate detection
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"
  
  # Enable sessions for ordered processing
  requires_session = false
}

# Storage Account for results and audit logs
resource "azurerm_storage_account" "main" {
  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  access_tier              = var.storage_access_tier
  
  # Security settings
  https_traffic_only_enabled = var.enable_https_only
  min_tls_version           = "TLS1_2"
  
  # Enable versioning and change feed
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    # Configure deletion retention
    delete_retention_policy {
      days = 30
    }
    
    # Configure container deletion retention
    container_delete_retention_policy {
      days = 30
    }
  }
  
  tags = local.common_tags

  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }
}

# Storage Account Network Rules (if firewall is enabled)
resource "azurerm_storage_account_network_rules" "main" {
  count = var.enable_storage_firewall ? 1 : 0
  
  storage_account_id = azurerm_storage_account.main.id
  
  default_action = "Deny"
  
  # Allow access from Azure services
  bypass = ["AzureServices"]
  
  # Allow access from Container Apps subnet (if using VNet integration)
  ip_rules = []
  
  depends_on = [
    azurerm_storage_container.moderation_results,
    azurerm_storage_container.audit_logs
  ]
}

# Storage Container for moderation results
resource "azurerm_storage_container" "moderation_results" {
  name                  = "moderation-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Storage Container for audit logs
resource "azurerm_storage_container" "audit_logs" {
  name                  = "audit-logs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_log_analytics ? 1 : 0
  
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                     = local.container_env_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  log_analytics_workspace_id = var.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
  
  # Enable workload profiles for enhanced features
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  
  tags = local.common_tags
}

# Container Apps Job for content processing
resource "azurerm_container_app_job" "content_processor" {
  name                         = local.container_job_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  
  # Job configuration
  replica_timeout_in_seconds = var.container_job_timeout
  replica_retry_limit        = var.container_job_retry_limit
  manual_trigger_config {
    parallelism              = var.container_job_parallelism
    replica_completion_count = 1
  }
  
  # Event-driven scaling configuration
  event_trigger_config {
    parallelism              = var.container_job_parallelism
    replica_completion_count = 1
    
    scale {
      min_executions = 0
      max_executions = 10
      
      rules {
        name = "service-bus-rule"
        type = "azure-servicebus"
        metadata = {
          queueName    = azurerm_servicebus_queue.content_queue.name
          messageCount = tostring(var.scale_rule_message_count)
          namespace    = azurerm_servicebus_namespace.main.name
        }
        
        # Authentication using managed identity
        auth {
          secret_name        = "service-bus-connection"
          trigger_parameter  = "connectionString"
        }
      }
    }
  }
  
  # Container configuration
  template {
    container {
      name   = "content-processor"
      image  = "mcr.microsoft.com/azure-cli:latest"
      cpu    = var.container_job_cpu
      memory = var.container_job_memory
      
      # Environment variables for content processing
      env {
        name  = "CONTENT_SAFETY_ENDPOINT"
        value = azurerm_cognitive_account.content_safety.endpoint
      }
      
      env {
        name        = "CONTENT_SAFETY_KEY"
        secret_name = "content-safety-key"
      }
      
      env {
        name        = "STORAGE_CONNECTION"
        secret_name = "storage-connection"
      }
      
      env {
        name        = "SERVICE_BUS_CONNECTION"
        secret_name = "service-bus-connection"
      }
      
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.enable_managed_identity ? "" : ""
      }
      
      # Startup command for content processing
      command = ["/bin/bash"]
      args = [
        "-c",
        <<-EOT
          # Install required tools
          apk add --no-cache curl jq
          
          # Content processing logic
          echo "Starting content processing job..."
          
          # Wait for Service Bus message (simplified for demo)
          sleep 10
          
          # Process content using Content Safety API
          echo "Processing content with Azure AI Content Safety..."
          
          # Sample content analysis (replace with actual Service Bus message processing)
          curl -X POST \
            "$CONTENT_SAFETY_ENDPOINT/contentsafety/text:analyze?api-version=2023-10-01" \
            -H "Ocp-Apim-Subscription-Key: $CONTENT_SAFETY_KEY" \
            -H "Content-Type: application/json" \
            -d '{"text": "Sample content for moderation", "categories": ["Hate", "SelfHarm", "Sexual", "Violence"]}' \
            > /tmp/analysis_result.json
          
          # Store results in Azure Storage
          echo "Storing results in Azure Storage..."
          
          # Create result file
          CONTENT_ID="sample-$(date +%s)"
          az storage blob upload \
            --file /tmp/analysis_result.json \
            --name "results/$CONTENT_ID.json" \
            --container-name moderation-results \
            --connection-string "$STORAGE_CONNECTION"
          
          # Create audit log
          cat > /tmp/audit.json << EOF
          {
            "contentId": "$CONTENT_ID",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "action": "content_moderation",
            "processor": "container-apps-job",
            "status": "completed"
          }
          EOF
          
          # Upload audit log
          az storage blob upload \
            --file /tmp/audit.json \
            --name "audit/$(date +%Y/%m/%d)/$CONTENT_ID.json" \
            --container-name audit-logs \
            --connection-string "$STORAGE_CONNECTION"
          
          echo "Content processing completed successfully"
        EOT
      ]
    }
  }
  
  # Secrets for secure configuration
  secret {
    name  = "content-safety-key"
    value = azurerm_cognitive_account.content_safety.primary_access_key
  }
  
  secret {
    name  = "storage-connection"
    value = azurerm_storage_account.main.primary_connection_string
  }
  
  secret {
    name  = "service-bus-connection"
    value = azurerm_servicebus_namespace.main.default_primary_connection_string
  }
  
  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_servicebus_queue.content_queue,
    azurerm_storage_container.moderation_results,
    azurerm_storage_container.audit_logs
  ]
}

# Action Group for alerts (if alerts are enabled)
resource "azurerm_monitor_action_group" "main" {
  count = var.enable_alerts ? 1 : 0
  
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ContentMod"
  
  # Email notification (if email is provided)
  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      name          = "Email Alert"
      email_address = var.alert_email
    }
  }
  
  # Webhook notification for integration with external systems
  webhook_receiver {
    name        = "Webhook Alert"
    service_uri = "https://example.com/webhook"
  }
  
  tags = local.common_tags
}

# Metric Alert for high queue depth
resource "azurerm_monitor_metric_alert" "high_queue_depth" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "High Content Queue Depth"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_servicebus_queue.content_queue.id]
  description         = "Alert when content queue has more than ${var.high_queue_depth_threshold} messages"
  
  # Alert configuration
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2
  
  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "ActiveMessages"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.high_queue_depth_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Metric Alert for failed job executions
resource "azurerm_monitor_metric_alert" "failed_jobs" {
  count = var.enable_alerts ? 1 : 0
  
  name                = "Failed Content Processing Jobs"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app_job.content_processor.id]
  description         = "Alert when content processing jobs fail"
  
  # Alert configuration
  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 1
  
  criteria {
    metric_namespace = "Microsoft.App/jobs"
    metric_name      = "JobExecutionFailures"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# RBAC assignments for managed identity access

# Grant Container Apps Job access to Service Bus
resource "azurerm_role_assignment" "container_to_servicebus" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_container_app_job.content_processor.identity[0].principal_id
}

# Grant Container Apps Job access to Storage Account
resource "azurerm_role_assignment" "container_to_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app_job.content_processor.identity[0].principal_id
}

# Grant Container Apps Job access to Content Safety
resource "azurerm_role_assignment" "container_to_content_safety" {
  scope                = azurerm_cognitive_account.content_safety.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_container_app_job.content_processor.identity[0].principal_id
}