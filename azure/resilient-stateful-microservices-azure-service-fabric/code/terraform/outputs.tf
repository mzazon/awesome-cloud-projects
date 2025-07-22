# Outputs for Azure Stateful Microservices Orchestration Infrastructure
# This file defines the outputs that will be displayed after successful deployment

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

# Service Fabric Cluster Information
output "service_fabric_cluster_name" {
  description = "Name of the Service Fabric cluster"
  value       = azurerm_service_fabric_cluster.main.name
}

output "service_fabric_cluster_id" {
  description = "ID of the Service Fabric cluster"
  value       = azurerm_service_fabric_cluster.main.id
}

output "service_fabric_management_endpoint" {
  description = "Management endpoint URL for the Service Fabric cluster"
  value       = azurerm_service_fabric_cluster.main.management_endpoint
}

output "service_fabric_cluster_endpoint" {
  description = "Client endpoint for the Service Fabric cluster"
  value       = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19000"
}

output "service_fabric_certificate_thumbprint" {
  description = "Thumbprint of the Service Fabric cluster certificate"
  value       = azurerm_key_vault_certificate.service_fabric.thumbprint
}

output "service_fabric_explorer_url" {
  description = "URL for Service Fabric Explorer"
  value       = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19080/Explorer"
}

# SQL Database Information
output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = azurerm_mssql_database.main.name
}

output "sql_database_id" {
  description = "ID of the SQL Database"
  value       = azurerm_mssql_database.main.id
}

output "sql_admin_login" {
  description = "Administrator login for SQL Server"
  value       = var.sql_admin_login
}

output "sql_connection_string" {
  description = "Connection string for SQL Database (without password)"
  value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.main.name};User ID=${var.sql_admin_login};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
  sensitive   = true
}

# Function App Information
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_windows_function_app.main.id
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_windows_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "function_app_orchestrator_url" {
  description = "URL for the Durable Functions orchestrator"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}/api/OrderProcessingOrchestrator"
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the Storage Account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_connection_string" {
  description = "Connection string for the Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Application Insights Information
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = azurerm_application_insights.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights instance"
  value       = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application ID for Application Insights"
  value       = azurerm_application_insights.main.app_id
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID for Log Analytics"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key for Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Networking Information
output "virtual_network_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "service_fabric_subnet_id" {
  description = "ID of the Service Fabric subnet"
  value       = azurerm_subnet.service_fabric.id
}

output "function_app_subnet_id" {
  description = "ID of the Function App subnet"
  value       = azurerm_subnet.function_app.id
}

output "network_security_group_id" {
  description = "ID of the Network Security Group"
  value       = azurerm_network_security_group.service_fabric.id
}

# Monitoring Information
output "action_group_name" {
  description = "Name of the Action Group for alerts"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the Action Group for alerts"
  value       = azurerm_monitor_action_group.main.id
}

# Connection and Configuration Information
output "deployment_summary" {
  description = "Summary of deployed resources and their endpoints"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    
    service_fabric = {
      name               = azurerm_service_fabric_cluster.main.name
      management_endpoint = azurerm_service_fabric_cluster.main.management_endpoint
      explorer_url       = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19080/Explorer"
      node_count         = var.service_fabric_node_count
      reliability_level  = var.service_fabric_reliability_level
    }
    
    sql_database = {
      server_name   = azurerm_mssql_server.main.name
      database_name = azurerm_mssql_database.main.name
      server_fqdn   = azurerm_mssql_server.main.fully_qualified_domain_name
      sku_name      = var.sql_database_sku
    }
    
    function_app = {
      name         = azurerm_windows_function_app.main.name
      url          = "https://${azurerm_windows_function_app.main.default_hostname}"
      orchestrator_url = "https://${azurerm_windows_function_app.main.default_hostname}/api/OrderProcessingOrchestrator"
      runtime_version = var.function_app_runtime_version
    }
    
    monitoring = {
      application_insights = azurerm_application_insights.main.name
      log_analytics       = azurerm_log_analytics_workspace.main.name
      key_vault          = azurerm_key_vault.main.name
    }
    
    storage = {
      account_name = azurerm_storage_account.main.name
      tier        = var.storage_account_tier
      replication = var.storage_account_replication_type
    }
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    key_vault_soft_delete_enabled = var.enable_key_vault_soft_delete
    sql_threat_detection_enabled  = var.enable_sql_threat_detection
    public_network_access_enabled = var.enable_public_network_access
    diagnostic_logs_enabled       = var.enable_diagnostic_logs
    
    certificates = {
      service_fabric_cert_thumbprint = azurerm_key_vault_certificate.service_fabric.thumbprint
    }
    
    network_security = {
      nsg_name = azurerm_network_security_group.service_fabric.name
      vnet_name = azurerm_virtual_network.main.name
    }
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Commands for post-deployment configuration and testing"
  value = {
    connect_to_service_fabric = "Connect-ServiceFabricCluster -ConnectionEndpoint ${azurerm_service_fabric_cluster.main.management_endpoint} -X509Credential -FindType FindByThumbprint -FindValue ${azurerm_key_vault_certificate.service_fabric.thumbprint} -StoreLocation CurrentUser -StoreName My"
    
    test_sql_connection = "sqlcmd -S ${azurerm_mssql_server.main.fully_qualified_domain_name} -d ${azurerm_mssql_database.main.name} -U ${var.sql_admin_login} -P [PASSWORD] -Q \"SELECT 1\""
    
    test_function_app = "curl -X POST 'https://${azurerm_windows_function_app.main.default_hostname}/api/OrderProcessingOrchestrator' -H 'Content-Type: application/json' -d '{\"OrderId\":\"TEST-001\",\"CustomerId\":\"CUST-123\",\"Amount\":99.99,\"ProductId\":\"PROD-456\",\"Quantity\":2}'"
    
    view_service_fabric_explorer = "https://${azurerm_service_fabric_cluster.main.name}.${var.location}.cloudapp.azure.com:19080/Explorer"
    
    view_application_insights = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main.id}/overview"
  }
}

# Cost Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization and resource management"
  value = {
    expensive_resources = [
      "Service Fabric cluster (${var.service_fabric_node_count} nodes of ${var.service_fabric_vm_size})",
      "SQL Database (${var.sql_database_sku} tier)",
      "Function App (${var.function_app_service_plan_sku} plan)"
    ]
    
    cost_reduction_tips = [
      "Delete Service Fabric cluster when not needed - most expensive component",
      "Use Basic tier for SQL Database in development environments",
      "Consider consumption plan for Function App in development",
      "Clean up storage account logs periodically",
      "Monitor Application Insights data retention settings"
    ]
    
    monitoring_costs = "Monitor costs in Azure Cost Management: https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/costanalysis"
  }
}

# Random generated values (for reference)
output "generated_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Tags applied to resources
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}