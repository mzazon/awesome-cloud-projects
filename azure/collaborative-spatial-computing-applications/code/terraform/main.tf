# Main Terraform configuration for Azure Spatial Computing Infrastructure
# This configuration deploys Azure Remote Rendering and Azure Spatial Anchors
# along with supporting storage and authentication infrastructure

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source to get current Azure AD client configuration
data "azuread_client_config" "current" {}

# Create Resource Group for all spatial computing resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    "resource-type" = "resource-group"
    "created-by"    = "terraform"
  })
}

# Azure Storage Account for 3D models and assets
# This storage account hosts 3D models, textures, and other assets
# used by Azure Remote Rendering for cloud-based 3D visualization
resource "azurerm_storage_account" "models" {
  name                = var.storage_account_name != "" ? var.storage_account_name : "st3dstorage${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Enable blob storage features for 3D content management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = var.enable_monitoring

    dynamic "delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = 7
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = 7
      }
    }
  }

  # Configure network access rules if IP ranges are specified
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.subnet_id != "" ? [var.subnet_id] : []
    }
  }

  tags = merge(var.tags, {
    "resource-type" = "storage-account"
    "purpose"       = "3d-assets-storage"
  })
}

# Blob container for 3D models and related assets
resource "azurerm_storage_container" "models" {
  name                  = var.blob_container_name
  storage_account_name  = azurerm_storage_account.models.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.models]
}

# Azure Remote Rendering Account
# Provides cloud-based GPU compute for rendering complex 3D models
# that exceed local device capabilities
resource "azurerm_mixed_reality_remote_rendering_account" "main" {
  name                = var.remote_rendering_account_name != "" ? var.remote_rendering_account_name : "arr-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku_name = var.remote_rendering_sku

  tags = merge(var.tags, {
    "resource-type" = "remote-rendering-account"
    "service"       = "azure-remote-rendering"
  })
}

# Azure Spatial Anchors Account
# Provides persistent spatial positioning and cross-device coordinate mapping
# for collaborative mixed reality experiences
resource "azurerm_mixed_reality_spatial_anchors_account" "main" {
  name                = var.spatial_anchors_account_name != "" ? var.spatial_anchors_account_name : "asa-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku_name = var.spatial_anchors_sku

  tags = merge(var.tags, {
    "resource-type" = "spatial-anchors-account"
    "service"       = "azure-spatial-anchors"
  })
}

# Application Insights for monitoring and telemetry
# Provides performance monitoring, usage analytics, and debugging capabilities
# for spatial computing applications
resource "azurerm_application_insights" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"

  tags = merge(var.tags, {
    "resource-type" = "application-insights"
    "purpose"       = "monitoring"
  })
}

# Log Analytics Workspace for centralized logging
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "law-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(var.tags, {
    "resource-type" = "log-analytics-workspace"
    "purpose"       = "centralized-logging"
  })
}

# Azure AD Application for service authentication
# Provides secure programmatic access to Mixed Reality services
resource "azuread_application" "spatial_app" {
  count = var.create_service_principal ? 1 : 0

  display_name = var.service_principal_display_name != "" ? var.service_principal_display_name : "SpatialApp-${var.project_name}-${random_string.suffix.result}"

  api {
    # Define application permissions for Mixed Reality services
    requested_access_token_version = 2
  }

  required_resource_access {
    # Microsoft Graph API permissions
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }

  # Configure application for Mixed Reality scenarios
  public_client {
    redirect_uris = [
      "https://login.microsoftonline.com/common/oauth2/nativeclient",
      "ms-appx-web://microsoft.aad.brokerplugin/${random_string.suffix.result}"
    ]
  }

  tags = ["spatial-computing", "mixed-reality", var.environment]
}

# Service Principal for the Azure AD Application
resource "azuread_service_principal" "spatial_app" {
  count = var.create_service_principal ? 1 : 0

  application_id               = azuread_application.spatial_app[0].application_id
  app_role_assignment_required = false

  tags = ["spatial-computing", "service-principal"]
}

# Service Principal Password (Client Secret)
resource "azuread_service_principal_password" "spatial_app" {
  count = var.create_service_principal ? 1 : 0

  service_principal_id = azuread_service_principal.spatial_app[0].object_id
  end_date_relative    = "8760h" # 1 year
}

# Role Assignment: Mixed Reality Administrator for Service Principal
resource "azurerm_role_assignment" "mixed_reality_admin" {
  count = var.create_service_principal ? 1 : 0

  scope                = azurerm_resource_group.main.id
  role_definition_name = "Mixed Reality Administrator"
  principal_id         = azuread_service_principal.spatial_app[0].object_id

  depends_on = [
    azurerm_mixed_reality_remote_rendering_account.main,
    azurerm_mixed_reality_spatial_anchors_account.main
  ]
}

# Role Assignment: Storage Blob Data Contributor for Service Principal
resource "azurerm_role_assignment" "storage_contributor" {
  count = var.create_service_principal ? 1 : 0

  scope                = azurerm_storage_account.models.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.spatial_app[0].object_id

  depends_on = [azurerm_storage_account.models]
}

# Budget alert for cost management
resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.enable_cost_alerts ? 1 : 0

  name              = "budget-${var.project_name}-${random_string.suffix.result}"
  resource_group_id = azurerm_resource_group.main.id

  amount     = var.monthly_budget_limit
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h"))
  }

  notification {
    enabled   = true
    threshold = 80
    operator  = "GreaterThan"

    contact_emails = []
  }

  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"

    contact_emails = []
  }
}

# Local file for Unity configuration
resource "local_file" "unity_config" {
  count = var.enable_unity_config_generation ? 1 : 0

  filename = "${var.unity_project_path}/Assets/StreamingAssets/AzureConfig.json"
  content = jsonencode({
    RemoteRenderingSettings = {
      AccountId        = azurerm_mixed_reality_remote_rendering_account.main.account_id
      AccountDomain    = azurerm_mixed_reality_remote_rendering_account.main.account_domain
      AccountKey       = "REPLACE_WITH_ACCOUNT_KEY"
      PreferredSessionSize = "Standard"
    }
    SpatialAnchorsSettings = {
      AccountId     = azurerm_mixed_reality_spatial_anchors_account.main.account_id
      AccountDomain = azurerm_mixed_reality_spatial_anchors_account.main.account_domain
      AccountKey    = "REPLACE_WITH_ACCOUNT_KEY"
    }
    ApplicationSettings = {
      MaxConcurrentSessions = var.max_concurrent_users
      SessionTimeoutMinutes = var.session_timeout_minutes
      AutoStartSession      = true
      EnableSpatialMapping  = true
      EnableHandTracking    = true
    }
    StorageSettings = {
      StorageAccountName = azurerm_storage_account.models.name
      ContainerName      = azurerm_storage_container.models.name
      StorageAccountKey  = "REPLACE_WITH_STORAGE_KEY"
    }
  })

  depends_on = [
    azurerm_mixed_reality_remote_rendering_account.main,
    azurerm_mixed_reality_spatial_anchors_account.main,
    azurerm_storage_account.models
  ]
}

# Local file for spatial synchronization configuration
resource "local_file" "spatial_sync_config" {
  count = var.enable_unity_config_generation ? 1 : 0

  filename = "${var.unity_project_path}/spatial-sync-config.json"
  content = jsonencode({
    SpatialSynchronization = {
      CoordinateSystem        = "WorldAnchor"
      SynchronizationMode     = "CloudBased"
      UpdateFrequencyHz       = 30
      PredictionBufferMs      = 100
      InterpolationEnabled    = true
      NetworkCompensation = {
        LatencyCompensation = true
        JitterReduction     = true
        PacketLossRecovery  = true
      }
    }
    DeviceCapabilities = {
      HoloLens = {
        SpatialMapping = true
        HandTracking   = true
        EyeTracking    = true
        VoiceCommands  = true
      }
      Mobile = {
        ARCore         = true
        ARKit          = true
        PlaneDetection = true
        TouchInput     = true
      }
    }
    CollaborationSettings = {
      MaxConcurrentUsers  = var.max_concurrent_users
      SpatialAnchorSharing = true
      GestureSharing      = true
      VoiceSharing        = false
    }
  })
}

# Data source for storage account primary access key
data "azurerm_storage_account" "models_data" {
  name                = azurerm_storage_account.models.name
  resource_group_name = azurerm_resource_group.main.name

  depends_on = [azurerm_storage_account.models]
}