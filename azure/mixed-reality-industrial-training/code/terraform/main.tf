# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current Azure AD context
data "azuread_client_config" "current" {}

# ==============================================================================
# RANDOM GENERATORS
# ==============================================================================

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate random password for potential use in configurations
resource "random_password" "app_secret" {
  length  = 32
  special = true
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create resource group for the industrial training platform
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    "Resource Type" = "Resource Group"
    "Created By"    = "Terraform"
  })
}

# ==============================================================================
# AZURE STORAGE ACCOUNT
# ==============================================================================

# Create storage account for 3D models and training content
resource "azurerm_storage_account" "training_storage" {
  name                     = var.storage_account_name != "" ? var.storage_account_name : "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  access_tier              = var.storage_account_access_tier

  # Security settings
  https_traffic_only_enabled = var.enable_https_traffic_only
  min_tls_version           = "TLS1_2"
  
  # Enable versioning and soft delete for data protection
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.storage_delete_retention_days
    }
    
    container_delete_retention_policy {
      days = var.storage_delete_retention_days
    }
  }

  # Configure public network access
  public_network_access_enabled = var.enable_public_network_access

  # Network rules for security
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules      = var.allowed_ip_ranges
      bypass        = ["AzureServices"]
    }
  }

  tags = merge(var.tags, {
    "Resource Type" = "Storage Account"
    "Purpose"       = "3D Models and Training Content"
  })
}

# Create container for 3D models
resource "azurerm_storage_container" "models_container" {
  name                  = "3d-models"
  storage_account_name  = azurerm_storage_account.training_storage.name
  container_access_type = "private"
}

# Create container for training content
resource "azurerm_storage_container" "training_container" {
  name                  = "training-content"
  storage_account_name  = azurerm_storage_account.training_storage.name
  container_access_type = "private"
}

# Create container for training scenarios
resource "azurerm_storage_container" "scenarios_container" {
  name                  = "training-scenarios"
  storage_account_name  = azurerm_storage_account.training_storage.name
  container_access_type = "private"
}

# Create container for user progress and analytics
resource "azurerm_storage_container" "analytics_container" {
  name                  = "analytics"
  storage_account_name  = azurerm_storage_account.training_storage.name
  container_access_type = "private"
}

# ==============================================================================
# AZURE REMOTE RENDERING ACCOUNT
# ==============================================================================

# Create Azure Remote Rendering account for cloud-based 3D rendering
resource "azurerm_mixed_reality_remote_rendering_account" "arr_account" {
  name                = var.remote_rendering_account_name != "" ? var.remote_rendering_account_name : "arr-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    "Resource Type" = "Remote Rendering Account"
    "Purpose"       = "Cloud-based 3D Rendering"
  })
}

# ==============================================================================
# AZURE SPATIAL ANCHORS ACCOUNT
# ==============================================================================

# Create Azure Spatial Anchors account for spatial positioning
resource "azurerm_mixed_reality_spatial_anchors_account" "spatial_anchors" {
  name                = var.spatial_anchors_account_name != "" ? var.spatial_anchors_account_name : "sa-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    "Resource Type" = "Spatial Anchors Account"
    "Purpose"       = "Spatial Positioning and Persistence"
  })
}

# ==============================================================================
# AZURE ACTIVE DIRECTORY APPLICATION
# ==============================================================================

# Create Azure AD application for authentication
resource "azuread_application" "training_app" {
  display_name     = var.ad_application_name != "" ? var.ad_application_name : "industrial-training-platform-${var.environment}-${random_string.suffix.result}"
  sign_in_audience = var.ad_application_sign_in_audience

  # Configure application for Mixed Reality services
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # Directory.Read.All
      type = "Role"
    }
  }

  # Configure web application settings
  web {
    homepage_url = "https://localhost:3000"
    
    redirect_uris = [
      "https://localhost:3000/auth/callback",
      "ms-appx-web://microsoft.aad.brokerplugin/${random_string.suffix.result}"
    ]
    
    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }

  # Configure public client settings for HoloLens
  public_client {
    redirect_uris = [
      "https://login.microsoftonline.com/common/oauth2/nativeclient"
    ]
  }

  tags = [
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "Purpose:Authentication"
  ]
}

# Create service principal for the application
resource "azuread_service_principal" "training_app_sp" {
  application_id = azuread_application.training_app.application_id
  
  tags = [
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "Purpose:Service Principal"
  ]
}

# Create application password (client secret)
resource "azuread_application_password" "training_app_secret" {
  application_object_id = azuread_application.training_app.object_id
  display_name          = "Training Platform Client Secret"
  end_date_relative     = "2160h" # 90 days
}

# ==============================================================================
# ROLE ASSIGNMENTS
# ==============================================================================

# Grant Storage Blob Data Contributor role to service principal
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.training_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.training_app_sp.object_id
}

# Grant Remote Rendering Client role to service principal
resource "azurerm_role_assignment" "arr_client" {
  scope                = azurerm_mixed_reality_remote_rendering_account.arr_account.id
  role_definition_name = "Remote Rendering Client"
  principal_id         = azuread_service_principal.training_app_sp.object_id
}

# Grant Spatial Anchors Account Contributor role to service principal
resource "azurerm_role_assignment" "spatial_anchors_contributor" {
  scope                = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.id
  role_definition_name = "Spatial Anchors Account Contributor"
  principal_id         = azuread_service_principal.training_app_sp.object_id
}

# ==============================================================================
# TRAINING PLATFORM CONFIGURATION
# ==============================================================================

# Upload training platform configuration as blob
resource "azurerm_storage_blob" "platform_config" {
  name                   = "platform-config.json"
  storage_account_name   = azurerm_storage_account.training_storage.name
  storage_container_name = azurerm_storage_container.training_container.name
  type                   = "Block"
  content_type          = "application/json"

  source_content = jsonencode({
    azureServices = {
      remoteRendering = {
        accountId       = azurerm_mixed_reality_remote_rendering_account.arr_account.account_id
        accountDomain   = azurerm_mixed_reality_remote_rendering_account.arr_account.account_domain
        serviceEndpoint = "https://remoterendering.${lower(replace(var.location, " ", ""))}.mixedreality.azure.com"
      }
      spatialAnchors = {
        accountId       = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.account_id
        accountDomain   = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.account_domain
        serviceEndpoint = "https://sts.${lower(replace(var.location, " ", ""))}.mixedreality.azure.com"
      }
      storage = {
        accountName        = azurerm_storage_account.training_storage.name
        modelsContainer    = azurerm_storage_container.models_container.name
        trainingContainer  = azurerm_storage_container.training_container.name
        scenariosContainer = azurerm_storage_container.scenarios_container.name
        analyticsContainer = azurerm_storage_container.analytics_container.name
      }
      azureAD = {
        tenantId    = data.azuread_client_config.current.tenant_id
        clientId    = azuread_application.training_app.application_id
        redirectUri = "ms-appx-web://microsoft.aad.brokerplugin/${azuread_application.training_app.application_id}"
      }
    }
    trainingPlatform = {
      sessionSettings = {
        maxConcurrentUsers = var.training_platform_settings.max_concurrent_users
        sessionTimeout     = var.training_platform_settings.session_timeout
        renderingQuality   = var.training_platform_settings.rendering_quality
        enableCollaboration = var.training_platform_settings.enable_collaboration
      }
      modelSettings = {
        lodLevels         = var.model_settings.lod_levels
        textureQuality    = var.model_settings.texture_quality
        enablePhysics     = var.model_settings.enable_physics
        enableInteraction = var.model_settings.enable_interaction
      }
      spatialSettings = {
        anchorPersistence  = var.spatial_settings.anchor_persistence
        roomScale         = var.spatial_settings.room_scale
        trackingAccuracy  = var.spatial_settings.tracking_accuracy
        enableWorldMapping = var.spatial_settings.enable_world_mapping
      }
    }
  })

  depends_on = [
    azurerm_storage_container.training_container
  ]
}

# Upload sample industrial model metadata
resource "azurerm_storage_blob" "pump_assembly_metadata" {
  name                   = "pump-assembly/metadata.json"
  storage_account_name   = azurerm_storage_account.training_storage.name
  storage_container_name = azurerm_storage_container.models_container.name
  type                   = "Block"
  content_type          = "application/json"

  source_content = jsonencode({
    name             = "Industrial Pump Assembly"
    description      = "High-pressure centrifugal pump for industrial applications"
    modelType        = "machinery"
    trainingScenarios = ["maintenance", "assembly", "troubleshooting"]
    complexity       = "high"
    polygonCount     = 2500000
    version          = "1.0"
    lastUpdated      = timestamp()
  })

  depends_on = [
    azurerm_storage_container.models_container
  ]
}

# Upload sample control panel metadata
resource "azurerm_storage_blob" "control_panel_metadata" {
  name                   = "control-panel/metadata.json"
  storage_account_name   = azurerm_storage_account.training_storage.name
  storage_container_name = azurerm_storage_container.models_container.name
  type                   = "Block"
  content_type          = "application/json"

  source_content = jsonencode({
    name             = "Industrial Control Panel"
    description      = "Programmable logic controller interface panel"
    modelType        = "controls"
    trainingScenarios = ["operation", "programming", "diagnostics"]
    complexity       = "medium"
    polygonCount     = 850000
    version          = "1.0"
    lastUpdated      = timestamp()
  })

  depends_on = [
    azurerm_storage_container.models_container
  ]
}

# Upload sample training scenario
resource "azurerm_storage_blob" "pump_maintenance_scenario" {
  name                   = "pump-maintenance.json"
  storage_account_name   = azurerm_storage_account.training_storage.name
  storage_container_name = azurerm_storage_container.scenarios_container.name
  type                   = "Block"
  content_type          = "application/json"

  source_content = jsonencode({
    scenarioId    = "pump-maintenance-001"
    title         = "Centrifugal Pump Maintenance Procedure"
    description   = "Step-by-step maintenance procedure for industrial centrifugal pumps"
    duration      = "45 minutes"
    difficulty    = "intermediate"
    prerequisites = ["basic-pump-knowledge", "safety-training"]
    objectives = [
      "Identify pump components and their functions",
      "Perform routine maintenance checks",
      "Troubleshoot common pump issues",
      "Document maintenance activities"
    ]
    steps = [
      {
        stepId         = 1
        title          = "Safety Lockout Procedure"
        description    = "Implement lockout/tagout safety procedures"
        duration       = "5 minutes"
        safetyRequired = true
      },
      {
        stepId             = 2
        title              = "Visual Inspection"
        description        = "Inspect pump housing and connections"
        duration           = "10 minutes"
        interactiveElements = ["pump-housing", "connections", "gauges"]
      },
      {
        stepId       = 3
        title        = "Performance Testing"
        description  = "Test pump performance and efficiency"
        duration     = "15 minutes"
        measurements = ["pressure", "flow-rate", "vibration"]
      }
    ]
    assessmentCriteria = {
      safety    = "mandatory"
      accuracy  = "85%"
      timeLimit = "60 minutes"
    }
    version     = "1.0"
    lastUpdated = timestamp()
  })

  depends_on = [
    azurerm_storage_container.scenarios_container
  ]
}

# Upload sample control panel training scenario
resource "azurerm_storage_blob" "control_panel_scenario" {
  name                   = "control-panel-operation.json"
  storage_account_name   = azurerm_storage_account.training_storage.name
  storage_container_name = azurerm_storage_container.scenarios_container.name
  type                   = "Block"
  content_type          = "application/json"

  source_content = jsonencode({
    scenarioId    = "control-panel-001"
    title         = "Industrial Control Panel Operation"
    description   = "Operating procedures for programmable logic controller interfaces"
    duration      = "30 minutes"
    difficulty    = "beginner"
    prerequisites = ["electrical-safety", "basic-controls"]
    objectives = [
      "Navigate control panel interface",
      "Monitor system parameters",
      "Respond to alarms and alerts",
      "Perform routine operations"
    ]
    steps = [
      {
        stepId             = 1
        title              = "System Startup"
        description        = "Power on and initialize control system"
        duration           = "5 minutes"
        interactiveElements = ["power-switch", "status-lights", "display"]
      },
      {
        stepId      = 2
        title       = "Parameter Monitoring"
        description = "Monitor key system parameters"
        duration    = "15 minutes"
        parameters  = ["temperature", "pressure", "flow-rate", "status"]
      },
      {
        stepId      = 3
        title       = "Alarm Response"
        description = "Respond to system alarms appropriately"
        duration    = "10 minutes"
        scenarios   = ["high-pressure", "low-flow", "system-fault"]
      }
    ]
    assessmentCriteria = {
      safety    = "mandatory"
      accuracy  = "90%"
      timeLimit = "45 minutes"
    }
    version     = "1.0"
    lastUpdated = timestamp()
  })

  depends_on = [
    azurerm_storage_container.scenarios_container
  ]
}