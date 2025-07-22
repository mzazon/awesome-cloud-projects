# ==============================================================================
# OUTPUTS - Azure Fraud Detection with AI Metrics Advisor and Immersive Reader
# ==============================================================================

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Azure AI Metrics Advisor Information
output "metrics_advisor_name" {
  description = "Name of the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.name
}

output "metrics_advisor_endpoint" {
  description = "Endpoint URL for the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.endpoint
}

output "metrics_advisor_id" {
  description = "ID of the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.id
}

output "metrics_advisor_key" {
  description = "Primary key for the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.primary_access_key
  sensitive   = true
}

output "metrics_advisor_secondary_key" {
  description = "Secondary key for the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.secondary_access_key
  sensitive   = true
}

output "metrics_advisor_custom_subdomain" {
  description = "Custom subdomain for the Azure AI Metrics Advisor service"
  value       = azurerm_cognitive_account.metrics_advisor.custom_subdomain_name
}

# Azure AI Immersive Reader Information
output "immersive_reader_name" {
  description = "Name of the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.name
}

output "immersive_reader_endpoint" {
  description = "Endpoint URL for the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.endpoint
}

output "immersive_reader_id" {
  description = "ID of the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.id
}

output "immersive_reader_key" {
  description = "Primary key for the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.primary_access_key
  sensitive   = true
}

output "immersive_reader_secondary_key" {
  description = "Secondary key for the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.secondary_access_key
  sensitive   = true
}

output "immersive_reader_custom_subdomain" {
  description = "Custom subdomain for the Azure AI Immersive Reader service"
  value       = azurerm_cognitive_account.immersive_reader.custom_subdomain_name
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.fraud_data.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.fraud_data.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.fraud_data.primary_blob_endpoint
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.fraud_data.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_key" {
  description = "Secondary access key for the storage account"
  value       = azurerm_storage_account.fraud_data.secondary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.fraud_data.primary_connection_string
  sensitive   = true
}

output "storage_containers" {
  description = "List of created storage containers"
  value       = [for container in azurerm_storage_container.containers : container.name]
}

# Logic App Information
output "logic_app_name" {
  description = "Name of the Logic App workflow"
  value       = azurerm_logic_app_workflow.fraud_processing.name
}

output "logic_app_id" {
  description = "ID of the Logic App workflow"
  value       = azurerm_logic_app_workflow.fraud_processing.id
}

output "logic_app_access_endpoint" {
  description = "Access endpoint for the Logic App workflow"
  value       = azurerm_logic_app_workflow.fraud_processing.access_endpoint
}

output "logic_app_callback_url" {
  description = "Callback URL for the Logic App workflow (HTTP trigger)"
  value       = "${azurerm_logic_app_workflow.fraud_processing.access_endpoint}/triggers/manual/paths/invoke?api-version=2016-10-01"
}

output "logic_app_managed_identity_principal_id" {
  description = "Principal ID of the Logic App managed identity"
  value       = azurerm_logic_app_workflow.fraud_processing.identity[0].principal_id
}

output "logic_app_managed_identity_tenant_id" {
  description = "Tenant ID of the Logic App managed identity"
  value       = azurerm_logic_app_workflow.fraud_processing.identity[0].tenant_id
}

# Log Analytics Workspace Information (if monitoring is enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].workspace_id : null
}

output "log_analytics_workspace_primary_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].primary_shared_key : null
  sensitive   = true
}

output "log_analytics_workspace_secondary_key" {
  description = "Secondary shared key for the Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].secondary_shared_key : null
  sensitive   = true
}

# Monitoring and Alerting Information
output "action_group_name" {
  description = "Name of the action group for fraud detection alerts"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_action_group.fraud_alerts[0].name : null
}

output "action_group_id" {
  description = "ID of the action group for fraud detection alerts"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_action_group.fraud_alerts[0].id : null
}

output "metrics_advisor_alert_rule_id" {
  description = "ID of the Metrics Advisor failure alert rule"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_metric_alert.metrics_advisor_failures[0].id : null
}

output "logic_app_alert_rule_id" {
  description = "ID of the Logic App failure alert rule"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_metric_alert.logic_app_failures[0].id : null
}

output "fraud_detection_alert_rule_id" {
  description = "ID of the high confidence fraud detection alert rule"
  value       = var.enable_monitoring && length(var.alert_email_addresses) > 0 ? azurerm_monitor_metric_alert.high_confidence_fraud[0].id : null
}

# Configuration and Settings
output "fraud_detection_threshold" {
  description = "Configured fraud detection threshold"
  value       = var.fraud_detection_threshold
}

output "processing_frequency_minutes" {
  description = "Configured processing frequency in minutes"
  value       = var.processing_frequency
}

output "supported_languages" {
  description = "List of supported languages for fraud alerts"
  value       = var.supported_languages
}

output "immersive_reader_features_enabled" {
  description = "Whether advanced Immersive Reader features are enabled"
  value       = var.enable_immersive_reader_features
}

# Security and Network Information
output "public_network_access_enabled" {
  description = "Whether public network access is enabled for cognitive services"
  value       = var.enable_public_network_access
}

output "allowed_ip_ranges" {
  description = "List of allowed IP ranges for service access"
  value       = var.allowed_ip_ranges
}

output "private_endpoints_enabled" {
  description = "Whether private endpoints are enabled"
  value       = var.enable_private_endpoints
}

# Environment and Deployment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# Connection Information for Applications
output "fraud_detection_configuration" {
  description = "Configuration object for fraud detection applications"
  value = {
    metrics_advisor = {
      endpoint          = azurerm_cognitive_account.metrics_advisor.endpoint
      name              = azurerm_cognitive_account.metrics_advisor.name
      custom_subdomain  = azurerm_cognitive_account.metrics_advisor.custom_subdomain_name
    }
    immersive_reader = {
      endpoint          = azurerm_cognitive_account.immersive_reader.endpoint
      name              = azurerm_cognitive_account.immersive_reader.name
      custom_subdomain  = azurerm_cognitive_account.immersive_reader.custom_subdomain_name
    }
    storage = {
      name              = azurerm_storage_account.fraud_data.name
      primary_endpoint  = azurerm_storage_account.fraud_data.primary_blob_endpoint
      containers        = [for container in azurerm_storage_container.containers : container.name]
    }
    logic_app = {
      name              = azurerm_logic_app_workflow.fraud_processing.name
      callback_url      = "${azurerm_logic_app_workflow.fraud_processing.access_endpoint}/triggers/manual/paths/invoke?api-version=2016-10-01"
      access_endpoint   = azurerm_logic_app_workflow.fraud_processing.access_endpoint
    }
    monitoring = {
      enabled           = var.enable_monitoring
      workspace_id      = var.enable_monitoring ? azurerm_log_analytics_workspace.fraud_monitoring[0].workspace_id : null
      alerting_enabled  = var.enable_monitoring && length(var.alert_email_addresses) > 0
    }
    settings = {
      fraud_threshold               = var.fraud_detection_threshold
      processing_frequency_minutes  = var.processing_frequency
      supported_languages          = var.supported_languages
      immersive_reader_features    = var.enable_immersive_reader_features
    }
  }
}

# Instructions for Next Steps
output "next_steps" {
  description = "Next steps for configuring the fraud detection system"
  value = <<-EOT
    
    ========================================================================
    Azure Fraud Detection System - Deployment Complete
    ========================================================================
    
    Your fraud detection system has been successfully deployed with the following components:
    
    1. Azure AI Metrics Advisor: ${azurerm_cognitive_account.metrics_advisor.name}
       - Endpoint: ${azurerm_cognitive_account.metrics_advisor.endpoint}
       - Custom Subdomain: ${azurerm_cognitive_account.metrics_advisor.custom_subdomain_name}
    
    2. Azure AI Immersive Reader: ${azurerm_cognitive_account.immersive_reader.name}
       - Endpoint: ${azurerm_cognitive_account.immersive_reader.endpoint}
       - Custom Subdomain: ${azurerm_cognitive_account.immersive_reader.custom_subdomain_name}
    
    3. Storage Account: ${azurerm_storage_account.fraud_data.name}
       - Containers: ${join(", ", [for container in azurerm_storage_container.containers : container.name])}
    
    4. Logic App Workflow: ${azurerm_logic_app_workflow.fraud_processing.name}
       - Callback URL: ${azurerm_logic_app_workflow.fraud_processing.access_endpoint}/triggers/manual/paths/invoke?api-version=2016-10-01
    
    ${var.enable_monitoring ? "5. Log Analytics Workspace: ${azurerm_log_analytics_workspace.fraud_monitoring[0].name}" : ""}
    ${var.enable_monitoring && length(var.alert_email_addresses) > 0 ? "6. Alert Rules: Configured for ${length(var.alert_email_addresses)} email recipient(s)" : ""}
    
    Next Steps:
    -----------
    1. Configure your financial data sources to send transaction data to the storage account
    2. Set up Metrics Advisor data feeds to monitor your financial metrics
    3. Test the Logic App workflow with sample fraud alerts
    4. Configure additional notification channels (Teams, SMS, etc.) as needed
    5. Review and adjust the fraud detection threshold based on your requirements
    
    Important Notes:
    ----------------
    - All services are configured with managed identities for secure access
    - Diagnostic logging is ${var.enable_diagnostic_logs ? "enabled" : "disabled"}
    - Public network access is ${var.enable_public_network_access ? "enabled" : "disabled"}
    - Private endpoints are ${var.enable_private_endpoints ? "enabled" : "disabled"}
    
    For detailed configuration and usage instructions, refer to the original recipe documentation.
    
    ========================================================================
    
  EOT
}