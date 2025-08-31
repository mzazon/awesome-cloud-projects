# Azure Communication Services Monitoring Infrastructure Outputs
# Essential information for verification, integration, and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Resource ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) for Log Analytics queries"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "log_analytics_secondary_shared_key" {
  description = "Secondary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.secondary_shared_key
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component"
  value       = azurerm_application_insights.main.id
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights component"
  value       = azurerm_application_insights.main.app_id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (legacy)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (modern approach)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Communication Services Information
output "communication_service_name" {
  description = "Name of the Communication Services resource"
  value       = azurerm_communication_service.main.name
}

output "communication_service_id" {
  description = "Resource ID of the Communication Services resource"
  value       = azurerm_communication_service.main.id
}

output "communication_service_primary_connection_string" {
  description = "Primary connection string for Communication Services"
  value       = azurerm_communication_service.main.primary_connection_string
  sensitive   = true
}

output "communication_service_secondary_connection_string" {
  description = "Secondary connection string for Communication Services"
  value       = azurerm_communication_service.main.secondary_connection_string
  sensitive   = true
}

output "communication_service_primary_key" {
  description = "Primary access key for Communication Services"
  value       = azurerm_communication_service.main.primary_key
  sensitive   = true
}

output "communication_service_secondary_key" {
  description = "Secondary access key for Communication Services"
  value       = azurerm_communication_service.main.secondary_key
  sensitive   = true
}

# Monitoring and Alerting Information
output "diagnostic_settings_enabled" {
  description = "Whether diagnostic settings are enabled"
  value       = var.enable_diagnostic_settings
}

output "metric_alerts_enabled" {
  description = "Whether metric alerts are enabled"
  value       = var.enable_metric_alerts
}

output "action_group_name" {
  description = "Name of the monitoring action group"
  value       = var.enable_metric_alerts ? azurerm_monitor_action_group.main[0].name : null
}

output "action_group_id" {
  description = "Resource ID of the monitoring action group"
  value       = var.enable_metric_alerts ? azurerm_monitor_action_group.main[0].id : null
}

output "alert_email_addresses" {
  description = "Email addresses configured for alert notifications"
  value       = var.alert_email_addresses
}

# KQL Query Examples for Log Analytics
output "monitoring_queries" {
  description = "Sample KQL queries for monitoring Communication Services"
  value = {
    # Email delivery monitoring query
    email_delivery_stats = <<-EOT
      ACSEmailSendMailOperational
      | where TimeGenerated >= ago(24h)
      | summarize 
          EmailsSent = count(),
          EmailsSuccessful = countif(Level == "Informational"),
          EmailsFailed = countif(Level == "Error")
      | extend SuccessRate = round((todouble(EmailsSuccessful) / todouble(EmailsSent)) * 100, 2)
      | project EmailsSent, EmailsSuccessful, EmailsFailed, SuccessRate
    EOT
    
    # SMS delivery monitoring query
    sms_delivery_stats = <<-EOT
      ACSSMSOperational
      | where TimeGenerated >= ago(24h)
      | summarize 
          MessagesSent = count(),
          MessagesDelivered = countif(DeliveryStatus == "Delivered"),
          MessagesFailed = countif(DeliveryStatus == "Failed")
      | extend SuccessRate = round((todouble(MessagesDelivered) / todouble(MessagesSent)) * 100, 2)
      | project MessagesSent, MessagesDelivered, MessagesFailed, SuccessRate
    EOT
    
    # Combined communication metrics query
    combined_metrics = <<-EOT
      union 
      (
          ACSEmailSendMailOperational
          | where TimeGenerated >= ago(24h)
          | summarize 
              TotalSent = count(),
              Successful = countif(Level == "Informational"),
              Failed = countif(Level == "Error")
          | extend ServiceType = "Email"
      ),
      (
          ACSSMSOperational  
          | where TimeGenerated >= ago(24h)
          | summarize 
              TotalSent = count(),
              Successful = countif(DeliveryStatus == "Delivered"),
              Failed = countif(DeliveryStatus == "Failed")
          | extend ServiceType = "SMS"
      )
      | extend SuccessRate = round((todouble(Successful) / todouble(TotalSent)) * 100, 2)
      | project ServiceType, TotalSent, Successful, Failed, SuccessRate
    EOT
    
    # API request monitoring query
    api_request_analysis = <<-EOT
      ACSAuthOperational
      | where TimeGenerated >= ago(24h)
      | summarize 
          TotalRequests = count(),
          SuccessfulRequests = countif(ResultCode == "Success"),
          FailedRequests = countif(ResultCode != "Success")
      by bin(TimeGenerated, 1h)
      | extend SuccessRate = round((todouble(SuccessfulRequests) / todouble(TotalRequests)) * 100, 2)
      | project TimeGenerated, TotalRequests, SuccessfulRequests, FailedRequests, SuccessRate
      | order by TimeGenerated desc
    EOT
  }
}

# Azure Monitor Workbook Templates
output "workbook_templates" {
  description = "Azure Monitor Workbook gallery templates for Communication Services monitoring"
  value = {
    communication_services_overview = "https://github.com/microsoft/Application-Insights-Workbooks/tree/master/Workbooks/Azure%20Communication%20Services"
    application_insights_overview  = "https://github.com/microsoft/Application-Insights-Workbooks/tree/master/Workbooks/Azure%20Monitor%20-%20Applications"
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Key endpoints and identifiers for application integration"
  value = {
    log_analytics_query_endpoint = "https://api.loganalytics.io/v1/workspaces/${azurerm_log_analytics_workspace.main.workspace_id}/query"
    application_insights_api_url = "https://api.applicationinsights.io/v1/apps/${azurerm_application_insights.main.app_id}"
    azure_portal_links = {
      resource_group        = "https://portal.azure.com/#@/resource${azurerm_resource_group.main.id}"
      log_analytics        = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.main.id}"
      application_insights = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}"
      communication_service = "https://portal.azure.com/#@/resource${azurerm_communication_service.main.id}"
    }
  }
}

# Cost Management Information
output "cost_management" {
  description = "Information for cost monitoring and optimization"
  value = {
    log_analytics_pricing_tier = var.log_analytics_sku
    log_analytics_retention    = var.log_analytics_retention_days
    log_analytics_daily_cap    = var.log_analytics_daily_quota_gb
    appinsights_daily_cap      = var.application_insights_daily_cap_gb
    appinsights_sampling       = var.application_insights_sampling_percentage
    estimated_monthly_cost     = "Review Azure Pricing Calculator for current rates based on data volume and retention settings"
  }
}

# Security and Compliance Information
output "security_configuration" {
  description = "Security and compliance configuration summary"
  value = {
    log_analytics_local_auth       = azurerm_log_analytics_workspace.main.local_authentication_enabled
    log_analytics_internet_access  = azurerm_log_analytics_workspace.main.internet_ingestion_enabled
    appinsights_ip_masking         = !azurerm_application_insights.main.disable_ip_masking
    diagnostic_settings_configured = var.enable_diagnostic_settings
    data_residency_location        = var.communication_service_data_location
  }
}