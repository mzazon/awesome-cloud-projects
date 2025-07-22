# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

# Create Storage Account for Functions and general storage
resource "azurerm_storage_account" "main" {
  name                     = "st${var.project_name}${var.environment}${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable static website for AR client assets
  static_website {
    index_document = "index.html"
  }
  
  # Configure blob properties for AR content
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "POST", "PUT", "DELETE"]
      allowed_origins    = var.allowed_origins
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    # Enable versioning for AR assets
    versioning_enabled = true
    
    # Configure delete retention
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "ai-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  retention_in_days   = var.log_retention_days
  
  tags = var.tags
}

# Create Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  
  tags = var.tags
}

# Create Azure Spatial Anchors Account
resource "azurerm_spatial_anchors_account" "main" {
  name                = var.spatial_anchors_account_name != "" ? var.spatial_anchors_account_name : "sa-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = var.tags
}

# Create Azure AD Application for Mixed Reality authentication
resource "azuread_application" "mixed_reality" {
  count            = var.enable_mixed_reality_authentication ? 1 : 0
  display_name     = "ARGaming-MR-${var.environment}-${random_id.suffix.hex}"
  sign_in_audience = "AzureADMyOrg"
  
  # Configure API permissions for Mixed Reality services
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  
  # Configure redirect URIs for mobile applications
  public_client {
    redirect_uris = [
      "https://localhost:3000/callback",
      "msauth://com.example.argaming/callback"
    ]
  }
}

# Create service principal for the Azure AD application
resource "azuread_service_principal" "mixed_reality" {
  count          = var.enable_mixed_reality_authentication ? 1 : 0
  application_id = azuread_application.mixed_reality[0].application_id
}

# Assign Spatial Anchors Account Reader role to the service principal
resource "azurerm_role_assignment" "spatial_anchors_reader" {
  count                = var.enable_mixed_reality_authentication ? 1 : 0
  scope                = azurerm_spatial_anchors_account.main.id
  role_definition_name = "Spatial Anchors Account Reader"
  principal_id         = azuread_service_principal.mixed_reality[0].object_id
}

# Create App Service Plan for Function App
resource "azurerm_service_plan" "function_app" {
  name                = "plan-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = var.function_app_service_plan_sku
  
  tags = var.tags
}

# Create Function App for location processing and game logic
resource "azurerm_windows_function_app" "main" {
  name                = var.function_app_name != "" ? var.function_app_name : "func-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_app.id
  
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  site_config {
    always_on = var.function_app_service_plan_sku != "Y1" # Always on not supported for Consumption plan
    
    application_stack {
      dotnet_version = var.function_dotnet_version
    }
    
    # Configure CORS for PlayFab integration
    cors {
      allowed_origins = var.allowed_origins
      support_credentials = true
    }
    
    # Enable Application Insights if configured
    application_insights_key = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    
    # Configure function runtime settings
    use_32_bit_worker = false
    
    # Set minimum TLS version for security
    minimum_tls_version = "1.2"
  }
  
  # Configure application settings
  app_settings = {
    "FUNCTIONS_EXTENSION_VERSION"        = var.function_runtime_version
    "FUNCTIONS_WORKER_RUNTIME"           = "dotnet-isolated"
    "WEBSITE_RUN_FROM_PACKAGE"          = "1"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"   = "true"
    
    # PlayFab configuration
    "PlayFabTitleId"                     = var.playfab_title_id
    "PlayFabSecretKey"                   = var.playfab_secret_key
    
    # Spatial Anchors configuration
    "SpatialAnchorsAccountId"            = azurerm_spatial_anchors_account.main.account_id
    "SpatialAnchorsAccountDomain"        = azurerm_spatial_anchors_account.main.account_domain
    "SpatialAnchorsAccountKey"           = azurerm_spatial_anchors_account.main.primary_access_key
    
    # Multiplayer configuration
    "MaxPlayersPerLocation"              = var.multiplayer_max_players_per_location
    "LocationRadius"                     = var.multiplayer_location_radius
    "SyncFrequency"                      = var.multiplayer_sync_frequency
    "RequiredARCapabilities"             = "PlaneDetection,LightEstimation"
    
    # Storage configuration
    "StorageConnectionString"            = azurerm_storage_account.main.primary_connection_string
    
    # Application Insights
    "APPINSIGHTS_INSTRUMENTATIONKEY"     = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : ""
    
    # Mixed Reality authentication
    "MixedRealityClientId"               = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].application_id : ""
    "MixedRealityTenantId"               = var.enable_mixed_reality_authentication ? data.azurerm_client_config.current.tenant_id : ""
    
    # Environment configuration
    "Environment"                        = var.environment
    "ProjectName"                        = var.project_name
    "ResourceGroup"                      = azurerm_resource_group.main.name
    "Location"                          = azurerm_resource_group.main.location
  }
  
  # Configure connection strings
  connection_string {
    name  = "DefaultConnection"
    type  = "SQLAzure"
    value = azurerm_storage_account.main.primary_connection_string
  }
  
  # Configure authentication if enabled
  dynamic "auth_settings" {
    for_each = var.enable_mixed_reality_authentication ? [1] : []
    content {
      enabled                        = true
      default_provider              = "AzureActiveDirectory"
      unauthenticated_client_action = "RedirectToLoginPage"
      
      active_directory {
        client_id         = azuread_application.mixed_reality[0].application_id
        client_secret     = "" # Will be configured separately for security
        allowed_audiences = [azuread_application.mixed_reality[0].application_id]
      }
    }
  }
  
  tags = var.tags
}

# Create Event Grid System Topic for Spatial Anchors events
resource "azurerm_eventgrid_system_topic" "spatial_anchors" {
  count               = var.enable_event_grid ? 1 : 0
  name                = "egt-spatial-anchors-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  source_arm_resource_id = azurerm_spatial_anchors_account.main.id
  topic_type          = "Microsoft.MixedReality.SpatialAnchorsAccounts"
  
  tags = var.tags
}

# Create Event Grid Subscription for spatial anchor events
resource "azurerm_eventgrid_event_subscription" "spatial_events" {
  count  = var.enable_event_grid ? 1 : 0
  name   = "spatial-anchor-events-${var.environment}-${random_id.suffix.hex}"
  scope  = azurerm_eventgrid_system_topic.spatial_anchors[0].id
  
  # Configure webhook endpoint
  webhook_endpoint {
    url = "https://${azurerm_windows_function_app.main.default_hostname}/api/ProcessSpatialEvent"
    
    # Configure endpoint properties
    max_events_per_batch              = 10
    preferred_batch_size_in_kilobytes = 64
  }
  
  # Configure event filtering
  included_event_types = [
    "Microsoft.MixedReality.SpatialAnchorsAccount.AnchorCreated",
    "Microsoft.MixedReality.SpatialAnchorsAccount.AnchorDeleted",
    "Microsoft.MixedReality.SpatialAnchorsAccount.AnchorUpdated"
  ]
  
  # Configure retry policy
  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440 # 24 hours
  }
  
  # Configure dead letter storage
  storage_blob_dead_letter_destination {
    storage_account_id          = azurerm_storage_account.main.id
    storage_blob_container_name = "eventgrid-deadletter"
  }
}

# Create storage container for dead letter events
resource "azurerm_storage_container" "deadletter" {
  count                = var.enable_event_grid ? 1 : 0
  name                 = "eventgrid-deadletter"
  storage_account_name = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create storage containers for AR content
resource "azurerm_storage_container" "ar_assets" {
  name                 = "ar-assets"
  storage_account_name = azurerm_storage_account.main.name
  container_access_type = "blob" # Public read access for AR assets
}

resource "azurerm_storage_container" "user_content" {
  name                 = "user-content"
  storage_account_name = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "game_state" {
  name                 = "game-state"
  storage_account_name = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Create Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = "standard"
  
  # Configure access policy for the current user/service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
    
    key_permissions = [
      "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore"
    ]
  }
  
  # Configure access policy for the Function App
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_windows_function_app.main.identity[0].principal_id
    
    secret_permissions = [
      "Get", "List"
    ]
  }
  
  # Configure network access
  network_acls {
    default_action = "Allow" # Change to "Deny" for production with VNet integration
    bypass         = "AzureServices"
  }
  
  tags = var.tags
}

# Store PlayFab secrets in Key Vault
resource "azurerm_key_vault_secret" "playfab_title_id" {
  count        = var.playfab_title_id != "" ? 1 : 0
  name         = "PlayFabTitleId"
  value        = var.playfab_title_id
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "playfab_secret_key" {
  count        = var.playfab_secret_key != "" ? 1 : 0
  name         = "PlayFabSecretKey"
  value        = var.playfab_secret_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Store Spatial Anchors key in Key Vault
resource "azurerm_key_vault_secret" "spatial_anchors_key" {
  name         = "SpatialAnchorsAccountKey"
  value        = azurerm_spatial_anchors_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault.main]
}

# Create managed identity for the Function App
resource "azurerm_user_assigned_identity" "function_app" {
  name                = "id-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = var.tags
}

# Assign the managed identity to the Function App
resource "azurerm_windows_function_app" "main_identity" {
  # This is a workaround to assign managed identity to the Function App
  # In a real scenario, you would configure this in the Function App resource
  depends_on = [azurerm_user_assigned_identity.function_app]
}

# Create diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  count              = var.enable_application_insights ? 1 : 0
  name               = "diag-${azurerm_windows_function_app.main.name}"
  target_resource_id = azurerm_windows_function_app.main.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Configure logs
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  # Configure metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "spatial_anchors" {
  count              = var.enable_application_insights ? 1 : 0
  name               = "diag-${azurerm_spatial_anchors_account.main.name}"
  target_resource_id = azurerm_spatial_anchors_account.main.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Configure metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "argaming"
  
  # Add webhook notification (customize as needed)
  webhook_receiver {
    name        = "webhook"
    service_uri = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
    use_common_alert_schema = true
  }
  
  tags = var.tags
}

# Create metric alerts for monitoring
resource "azurerm_monitor_metric_alert" "function_app_errors" {
  count               = var.enable_application_insights ? 1 : 0
  name                = "alert-function-errors-${var.environment}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_windows_function_app.main.id]
  description         = "Alert when Function App error rate is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = var.tags
}

# Create budget for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${var.project_name}-${var.environment}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = 100 # Monthly budget in USD
  time_grain = "Monthly"
  
  time_period {
    start_date = "2024-01-01T00:00:00Z"
    end_date   = "2025-12-31T23:59:59Z"
  }
  
  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"
    
    contact_emails = [
      "admin@example.com"
    ]
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    
    contact_emails = [
      "admin@example.com"
    ]
  }
}

# Output important resource information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "spatial_anchors_account_id" {
  description = "ID of the Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.account_id
}

output "spatial_anchors_account_domain" {
  description = "Domain of the Spatial Anchors account"
  value       = azurerm_spatial_anchors_account.main.account_domain
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_windows_function_app.main.name
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_windows_function_app.main.default_hostname}"
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : "Not configured"
  sensitive   = true
}

output "mixed_reality_client_id" {
  description = "Azure AD application client ID for Mixed Reality"
  value       = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].application_id : "Not configured"
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "unity_config" {
  description = "Configuration for Unity client"
  value = {
    PlayFabTitleId            = var.playfab_title_id
    SpatialAnchorsAccountId   = azurerm_spatial_anchors_account.main.account_id
    SpatialAnchorsAccountDomain = azurerm_spatial_anchors_account.main.account_domain
    FunctionAppEndpoint       = "https://${azurerm_windows_function_app.main.default_hostname}"
    StorageAccountName        = azurerm_storage_account.main.name
    ApplicationInsightsKey    = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : "Not configured"
    MixedRealityClientId      = var.enable_mixed_reality_authentication ? azuread_application.mixed_reality[0].application_id : "Not configured"
  }
  sensitive = true
}