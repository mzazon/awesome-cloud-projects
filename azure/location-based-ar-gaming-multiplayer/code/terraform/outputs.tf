# Core Infrastructure Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Spatial Anchors Outputs
output "spatial_anchors_account_name" {
  description = "Name of the Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.name
}

output "spatial_anchors_account_id" {
  description = "ID of the Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.account_id
}

output "spatial_anchors_account_domain" {
  description = "Domain of the Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.account_domain
}

output "spatial_anchors_primary_access_key" {
  description = "Primary access key for Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.primary_access_key
  sensitive   = true
}

output "spatial_anchors_secondary_access_key" {
  description = "Secondary access key for Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.secondary_access_key
  sensitive   = true
}

# Function App Outputs
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "function_app_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_windows_function_app.main.default_hostname
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's managed identity"
  value       = azurerm_windows_function_app.main.identity[0].principal_id
}

output "function_app_outbound_ip_addresses" {
  description = "Outbound IP addresses of the Function App"
  value       = azurerm_windows_function_app.main.outbound_ip_addresses
}

output "function_app_possible_outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Function App"
  value       = azurerm_windows_function_app.main.possible_outbound_ip_addresses
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_account_secondary_connection_string" {
  description = "Secondary connection string for the storage account"
  value       = azurerm_storage_account.main.secondary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_secondary_access_key" {
  description = "Secondary access key for the storage account"
  value       = azurerm_storage_account.main.secondary_access_key
  sensitive   = true
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_web_endpoint" {
  description = "Primary web endpoint for the storage account"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

# Storage Container Outputs
output "ar_assets_container_name" {
  description = "Name of the AR assets container"
  value       = azurerm_storage_container.ar_assets.name
}

output "user_content_container_name" {
  description = "Name of the user content container"
  value       = azurerm_storage_container.user_content.name
}

output "game_state_container_name" {
  description = "Name of the game state container"
  value       = azurerm_storage_container.game_state.name
}

# Application Insights Outputs
output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not configured"
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : "Not configured"
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : "Not configured"
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].app_id : "Not configured"
}

# Log Analytics Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

# Mixed Reality Authentication Outputs
output "mixed_reality_application_name" {
  description = "Display name of the Mixed Reality Azure AD application"
  value       = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].display_name : "Not configured"
}

output "mixed_reality_client_id" {
  description = "Azure AD application client ID for Mixed Reality"
  value       = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].application_id : "Not configured"
}

output "mixed_reality_service_principal_id" {
  description = "Service principal ID for Mixed Reality application"
  value       = var.enable_mixed_reality_authentication ? azuread_service_principal.mixed_reality[0].object_id : "Not configured"
}

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Event Grid Outputs
output "event_grid_system_topic_name" {
  description = "Name of the Event Grid system topic"
  value       = var.enable_event_grid ? azurerm_eventgrid_system_topic.spatial_anchors[0].name : "Not configured"
}

output "event_grid_subscription_name" {
  description = "Name of the Event Grid subscription"
  value       = var.enable_event_grid ? azurerm_eventgrid_event_subscription.spatial_events[0].name : "Not configured"
}

output "event_grid_webhook_endpoint" {
  description = "Event Grid webhook endpoint URL"
  value       = var.enable_event_grid ? "https://${azurerm_windows_function_app.main.default_hostname}/api/ProcessSpatialEvent" : "Not configured"
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

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

# Service Plan Outputs
output "service_plan_name" {
  description = "Name of the App Service Plan"
  value       = azurerm_service_plan.function_app.name
}

output "service_plan_sku" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.function_app.sku_name
}

output "service_plan_os_type" {
  description = "OS type of the App Service Plan"
  value       = azurerm_service_plan.function_app.os_type
}

# Monitoring Outputs
output "action_group_name" {
  description = "Name of the monitor action group"
  value       = azurerm_monitor_action_group.main.name
}

output "action_group_id" {
  description = "ID of the monitor action group"
  value       = azurerm_monitor_action_group.main.id
}

# API Endpoints for Unity Client
output "api_endpoints" {
  description = "API endpoints for Unity client integration"
  value = {
    create_anchor       = "https://${azurerm_windows_function_app.main.default_hostname}/api/CreateAnchor"
    configure_lobby     = "https://${azurerm_windows_function_app.main.default_hostname}/api/ConfigureLobby"
    process_spatial_event = "https://${azurerm_windows_function_app.main.default_hostname}/api/ProcessSpatialEvent"
    health_check        = "https://${azurerm_windows_function_app.main.default_hostname}/api/health"
  }
}

# Unity Client Configuration
output "unity_config_json" {
  description = "Complete Unity client configuration in JSON format"
  value = jsonencode({
    PlayFabSettings = {
      TitleId           = var.playfab_title_id
      DeveloperSecretKey = var.playfab_secret_key
    }
    SpatialAnchorsSettings = {
      AccountId     = azurerm_spatial_anchors_account.main.account_id
      AccountDomain = azurerm_spatial_anchors_account.main.account_domain
      AccountKey    = azurerm_spatial_anchors_account.main.primary_access_key
    }
    FunctionEndpoints = {
      CreateAnchor    = "https://${azurerm_windows_function_app.main.default_hostname}/api/CreateAnchor"
      ConfigureLobby  = "https://${azurerm_windows_function_app.main.default_hostname}/api/ConfigureLobby"
      ProcessSpatialEvent = "https://${azurerm_windows_function_app.main.default_hostname}/api/ProcessSpatialEvent"
    }
    StorageSettings = {
      AccountName       = azurerm_storage_account.main.name
      ConnectionString  = azurerm_storage_account.main.primary_connection_string
      ARAssetsContainer = azurerm_storage_container.ar_assets.name
      UserContentContainer = azurerm_storage_container.user_content.name
      GameStateContainer = azurerm_storage_container.game_state.name
    }
    ApplicationInsights = {
      InstrumentationKey = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
      ConnectionString   = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    }
    MixedRealityAuth = {
      ClientId  = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].application_id : ""
      TenantId  = data.azurerm_client_config.current.tenant_id
    }
    MultiplayerSettings = {
      MaxPlayersPerLocation = var.multiplayer_max_players_per_location
      LocationRadius       = var.multiplayer_location_radius
      SyncFrequency        = var.multiplayer_sync_frequency
      RequiredARCapabilities = ["PlaneDetection", "LightEstimation"]
    }
    Environment = {
      Name          = var.environment
      ProjectName   = var.project_name
      ResourceGroup = azurerm_resource_group.main.name
      Location      = azurerm_resource_group.main.location
    }
  })
  sensitive = true
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group          = azurerm_resource_group.main.name
    location               = azurerm_resource_group.main.location
    environment            = var.environment
    project_name           = var.project_name
    spatial_anchors_account = azurerm_spatial_anchors_account.main.name
    function_app           = azurerm_windows_function_app.main.name
    storage_account        = azurerm_storage_account.main.name
    key_vault             = azurerm_key_vault.main.name
    application_insights   = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not configured"
    mixed_reality_auth     = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].display_name : "Not configured"
    event_grid            = var.enable_event_grid ? azurerm_eventgrid_system_topic.spatial_anchors[0].name : "Not configured"
    estimated_monthly_cost = "~$20-50 USD (depends on usage)"
  }
}

# Connection Instructions
output "connection_instructions" {
  description = "Instructions for connecting to the deployed resources"
  value = {
    function_app_url = "https://${azurerm_windows_function_app.main.default_hostname}"
    storage_account_url = azurerm_storage_account.main.primary_web_endpoint
    key_vault_url = azurerm_key_vault.main.vault_uri
    application_insights_url = var.enable_application_insights ? "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_application_insights.main[0].id}/overview" : "Not configured"
    spatial_anchors_portal_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_spatial_anchors_account.main.id}/overview"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Configure PlayFab Title ID and Secret Key in the Function App settings",
    "2. Deploy Function App code for anchor management and lobby configuration",
    "3. Configure Unity client with the provided configuration JSON",
    "4. Test spatial anchor creation and multiplayer lobby functionality",
    "5. Upload AR assets to the ar-assets storage container",
    "6. Configure custom domain and SSL certificate if needed",
    "7. Set up monitoring alerts and notifications",
    "8. Review and adjust budget limits based on usage patterns"
  ]
}