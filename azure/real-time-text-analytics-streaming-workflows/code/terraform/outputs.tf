# Resource Group Output
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Cognitive Services Outputs
output "cognitive_services_name" {
  description = "Name of the Cognitive Services Text Analytics resource"
  value       = azurerm_cognitive_account.text_analytics.name
}

output "cognitive_services_endpoint" {
  description = "Endpoint URL for the Cognitive Services Text Analytics resource"
  value       = azurerm_cognitive_account.text_analytics.endpoint
}

output "cognitive_services_key" {
  description = "Primary access key for Cognitive Services (sensitive)"
  value       = azurerm_cognitive_account.text_analytics.primary_access_key
  sensitive   = true
}

output "cognitive_services_location" {
  description = "Location of the Cognitive Services resource"
  value       = azurerm_cognitive_account.text_analytics.location
}

# Event Hub Outputs
output "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  value       = azurerm_eventhub_namespace.main.name
}

output "event_hub_name" {
  description = "Name of the Event Hub"
  value       = azurerm_eventhub.content_stream.name
}

output "event_hub_connection_string" {
  description = "Connection string for sending events to Event Hub (sensitive)"
  value       = azurerm_eventhub_authorization_rule.send_policy.primary_connection_string
  sensitive   = true
}

output "event_hub_logic_app_connection_string" {
  description = "Connection string for Logic Apps Event Hub access (sensitive)"
  value       = azurerm_eventhub_authorization_rule.logic_app_policy.primary_connection_string
  sensitive   = true
}

output "event_hub_namespace_fqdn" {
  description = "Fully qualified domain name of the Event Hub namespace"
  value       = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_container_names" {
  description = "Names of the created storage containers"
  value = {
    processed_insights  = azurerm_storage_container.processed_insights.name
    raw_content        = azurerm_storage_container.raw_content.name
    sentiment_archives = azurerm_storage_container.sentiment_archives.name
  }
}

# Logic App Outputs
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.content_processor[0].name : null
}

output "logic_app_id" {
  description = "Resource ID of the Logic App workflow"
  value       = var.logic_app_enabled ? azurerm_logic_app_workflow.content_processor[0].id : null
}

output "logic_app_callback_url" {
  description = "Callback URL for the Logic App HTTP trigger"
  value       = var.logic_app_enabled ? azurerm_logic_app_trigger_http_request.content_trigger[0].callback_url : null
  sensitive   = true
}

# API Connection Outputs
output "api_connections" {
  description = "Information about created API connections"
  value = var.logic_app_enabled ? {
    eventhub_connection = {
      name = azurerm_api_connection.eventhub[0].name
      id   = azurerm_api_connection.eventhub[0].id
    }
    cognitive_services_connection = {
      name = azurerm_api_connection.cognitive_services[0].name
      id   = azurerm_api_connection.cognitive_services[0].id
    }
    azureblob_connection = {
      name = azurerm_api_connection.azureblob[0].name
      id   = azurerm_api_connection.azureblob[0].id
    }
  } : null
}

# Monitoring Outputs
output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (sensitive)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (sensitive)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_secret_names" {
  description = "Names of secrets stored in Key Vault"
  value = {
    cognitive_key      = azurerm_key_vault_secret.cognitive_key.name
    eventhub_connection = azurerm_key_vault_secret.eventhub_connection.name
    storage_connection  = azurerm_key_vault_secret.storage_connection.name
  }
}

# Alert Configuration Outputs
output "action_group_name" {
  description = "Name of the monitor action group"
  value       = azurerm_monitor_action_group.alerts.name
}

output "alert_email" {
  description = "Email address configured for alerts"
  value       = var.alert_email
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    resource_group     = azurerm_resource_group.main.name
    location          = azurerm_resource_group.main.location
    cognitive_service = azurerm_cognitive_account.text_analytics.name
    event_hub_namespace = azurerm_eventhub_namespace.main.name
    event_hub         = azurerm_eventhub.content_stream.name
    storage_account   = azurerm_storage_account.main.name
    logic_app         = var.logic_app_enabled ? azurerm_logic_app_workflow.content_processor[0].name : "disabled"
    key_vault         = azurerm_key_vault.main.name
    monitoring_enabled = true
    alerts_configured  = true
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    event_hub_fqdn = "${azurerm_eventhub_namespace.main.name}.servicebus.windows.net"
    event_hub_name = azurerm_eventhub.content_stream.name
    cognitive_endpoint = azurerm_cognitive_account.text_analytics.endpoint
    next_steps = [
      "Use the Event Hub connection string to send content for processing",
      "Monitor processing through Application Insights dashboard",
      "Check processed results in the storage account containers",
      "Configure Logic App workflow for automated content processing",
      "Set up additional alert rules as needed for your use case"
    ]
  }
}

# Testing Information
output "testing_info" {
  description = "Information for testing the deployed infrastructure"
  value = {
    test_message_format = {
      content   = "Text content to analyze"
      source    = "source-identifier"
      timestamp = "ISO 8601 timestamp"
    }
    validation_commands = [
      "az eventhub show --name content-stream --namespace-name ${azurerm_eventhub_namespace.main.name} --resource-group ${azurerm_resource_group.main.name}",
      "az cognitiveservices account show --name ${azurerm_cognitive_account.text_analytics.name} --resource-group ${azurerm_resource_group.main.name}",
      "az storage container list --account-name ${azurerm_storage_account.main.name}"
    ]
  }
}