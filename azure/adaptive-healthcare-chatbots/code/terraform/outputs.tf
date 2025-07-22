# Outputs for Azure Healthcare Chatbot Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure Health Bot Outputs
output "health_bot_name" {
  description = "Name of the Azure Health Bot instance"
  value       = azurerm_healthbot.main.name
}

output "health_bot_management_portal_url" {
  description = "URL to the Health Bot management portal"
  value       = "https://portal.healthbot.microsoft.com/account/${azurerm_healthbot.main.name}"
  sensitive   = false
}

output "health_bot_webhook_secret" {
  description = "Webhook secret for Health Bot integration"
  value       = "Configure in Health Bot portal after deployment"
  sensitive   = false
}

# Azure Personalizer Outputs
output "personalizer_name" {
  description = "Name of the Azure Personalizer service"
  value       = azurerm_cognitive_account.personalizer.name
}

output "personalizer_endpoint" {
  description = "Endpoint URL for Azure Personalizer"
  value       = azurerm_cognitive_account.personalizer.endpoint
}

output "personalizer_key_vault_secret_name" {
  description = "Name of the Key Vault secret containing Personalizer key"
  value       = azurerm_key_vault_secret.personalizer_key.name
}

# SQL Managed Instance Outputs
output "sql_managed_instance_name" {
  description = "Name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.name
}

output "sql_managed_instance_fqdn" {
  description = "Fully qualified domain name of the SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.fqdn
}

output "sql_admin_username" {
  description = "Administrator username for SQL Managed Instance"
  value       = azurerm_mssql_managed_instance.main.administrator_login
}

output "sql_connection_string_template" {
  description = "Template for SQL connection string (password from Key Vault)"
  value       = "Server=${azurerm_mssql_managed_instance.main.fqdn};Database=HealthBotDB;User Id=${azurerm_mssql_managed_instance.main.administrator_login};Password=<from-key-vault>;Encrypt=true;TrustServerCertificate=false;"
  sensitive   = false
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_url" {
  description = "Default hostname of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App managed identity"
  value       = azurerm_windows_function_app.main.identity[0].principal_id
}

# API Management Outputs
output "api_management_name" {
  description = "Name of the API Management service"
  value       = azurerm_api_management.main.name
}

output "api_management_gateway_url" {
  description = "Gateway URL for API Management"
  value       = azurerm_api_management.main.gateway_url
}

output "api_management_portal_url" {
  description = "Portal URL for API Management"
  value       = azurerm_api_management.main.portal_url
}

output "api_management_management_url" {
  description = "Management API URL"
  value       = azurerm_api_management.main.management_api_url
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

output "key_vault_secrets" {
  description = "List of secrets stored in Key Vault"
  value = {
    sql_admin_password = azurerm_key_vault_secret.sql_admin_password.name
    personalizer_key   = azurerm_key_vault_secret.personalizer_key.name
  }
}

# Network Outputs
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "sql_mi_subnet_id" {
  description = "ID of the SQL Managed Instance subnet"
  value       = azurerm_subnet.sql_mi.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account for Function App"
  value       = azurerm_storage_account.function_app.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.function_app.primary_blob_endpoint
}

# Monitoring Outputs (if enabled)
output "application_insights_name" {
  description = "Name of Application Insights instance"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of Log Analytics workspace"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].workspace_id : null
}

# Private Endpoint Outputs (if enabled)
output "private_endpoints" {
  description = "Information about private endpoints"
  value = var.enable_private_endpoints ? {
    key_vault_pe_name    = azurerm_private_endpoint.key_vault[0].name
    personalizer_pe_name = azurerm_private_endpoint.personalizer[0].name
  } : null
}

# Deployment Information
output "deployment_info" {
  description = "Important deployment information and next steps"
  value = {
    environment           = var.environment
    hipaa_compliance     = var.enable_hipaa_compliance
    monitoring_enabled   = var.enable_monitoring
    private_endpoints    = var.enable_private_endpoints
    resource_group       = azurerm_resource_group.main.name
    deployment_timestamp = timestamp()
  }
}

# Post-Deployment Instructions
output "post_deployment_instructions" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    NEXT STEPS AFTER DEPLOYMENT:
    
    1. SQL Managed Instance Setup (may take 4-6 hours to complete):
       - Wait for SQL MI deployment to complete
       - Connect to: ${azurerm_mssql_managed_instance.main.fqdn}
       - Create HealthBotDB database
       - Run schema creation scripts
    
    2. Health Bot Configuration:
       - Access management portal: https://portal.healthbot.microsoft.com/account/${azurerm_healthbot.main.name}
       - Configure scenarios and triggers
       - Set up webhook integration with Function App
    
    3. Function App Deployment:
       - Deploy integration functions to: ${azurerm_windows_function_app.main.name}
       - Configure function triggers and bindings
       - Test Personalizer integration
    
    4. API Management Setup:
       - Configure API policies in: ${azurerm_api_management.main.name}
       - Set up subscription keys and access control
       - Configure Health Bot API integration
    
    5. Monitoring and Compliance:
       - Review Application Insights dashboards (if enabled)
       - Configure alerts and notifications
       - Validate HIPAA compliance settings
    
    6. Security Validation:
       - Verify Key Vault access policies
       - Test private endpoint connectivity (if enabled)
       - Review network security group rules
    
    Important URLs:
    - Health Bot Portal: https://portal.healthbot.microsoft.com/account/${azurerm_healthbot.main.name}
    - Function App: https://${azurerm_windows_function_app.main.default_hostname}
    - API Management: ${azurerm_api_management.main.gateway_url}
    - Key Vault: ${azurerm_key_vault.main.vault_uri}
  EOT
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs in non-production environments"
  value = <<-EOT
    COST OPTIMIZATION TIPS:
    
    Development Environment:
    - Use F0 (Free) tier for Health Bot and Personalizer
    - Consider smaller SQL MI configuration (4 vCores, 32GB storage)
    - Use Consumption plan for Function App
    - Use Developer tier for API Management
    
    Production Environment:
    - Monitor usage and scale accordingly
    - Implement auto-scaling policies
    - Use Reserved Instances for predictable workloads
    - Regular cost analysis and optimization reviews
    
    Current Configuration:
    - Health Bot SKU: ${var.health_bot_sku}
    - Personalizer SKU: ${var.personalizer_sku}
    - SQL MI vCores: ${var.sql_vcores}
    - Function App Plan: ${var.function_app_service_plan_sku}
    - API Management: ${var.apim_sku_name}
  EOT
}

# Security and Compliance Summary
output "security_compliance_summary" {
  description = "Summary of security and compliance features"
  value = {
    hipaa_compliance_enabled = var.enable_hipaa_compliance
    private_endpoints_enabled = var.enable_private_endpoints
    key_vault_rbac = true
    sql_mi_tls_version = "1.2"
    storage_encryption = true
    function_app_https_only = true
    data_classification = var.data_classification
    audit_logging = var.enable_monitoring
  }
}