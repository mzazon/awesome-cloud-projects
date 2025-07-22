# ==============================================================================
# RESOURCE GROUP OUTPUTS
# ==============================================================================

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

# ==============================================================================
# AZURE REMOTE RENDERING OUTPUTS
# ==============================================================================

output "remote_rendering_account_name" {
  description = "Name of the Azure Remote Rendering account"
  value       = azurerm_mixed_reality_remote_rendering_account.arr_account.name
}

output "remote_rendering_account_id" {
  description = "Account ID for Azure Remote Rendering service"
  value       = azurerm_mixed_reality_remote_rendering_account.arr_account.account_id
}

output "remote_rendering_account_domain" {
  description = "Account domain for Azure Remote Rendering service"
  value       = azurerm_mixed_reality_remote_rendering_account.arr_account.account_domain
}

output "remote_rendering_service_endpoint" {
  description = "Service endpoint for Azure Remote Rendering"
  value       = "https://remoterendering.${lower(replace(var.location, " ", ""))}.mixedreality.azure.com"
}

# ==============================================================================
# AZURE SPATIAL ANCHORS OUTPUTS
# ==============================================================================

output "spatial_anchors_account_name" {
  description = "Name of the Azure Spatial Anchors account"
  value       = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.name
}

output "spatial_anchors_account_id" {
  description = "Account ID for Azure Spatial Anchors service"
  value       = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.account_id
}

output "spatial_anchors_account_domain" {
  description = "Account domain for Azure Spatial Anchors service"
  value       = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.account_domain
}

output "spatial_anchors_service_endpoint" {
  description = "Service endpoint for Azure Spatial Anchors"
  value       = "https://sts.${lower(replace(var.location, " ", ""))}.mixedreality.azure.com"
}

# ==============================================================================
# AZURE STORAGE OUTPUTS
# ==============================================================================

output "storage_account_name" {
  description = "Name of the Azure Storage account"
  value       = azurerm_storage_account.training_storage.name
}

output "storage_account_id" {
  description = "ID of the Azure Storage account"
  value       = azurerm_storage_account.training_storage.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.training_storage.primary_blob_endpoint
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.training_storage.primary_connection_string
  sensitive   = true
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.training_storage.primary_access_key
  sensitive   = true
}

# ==============================================================================
# STORAGE CONTAINER OUTPUTS
# ==============================================================================

output "models_container_name" {
  description = "Name of the 3D models storage container"
  value       = azurerm_storage_container.models_container.name
}

output "training_container_name" {
  description = "Name of the training content storage container"
  value       = azurerm_storage_container.training_container.name
}

output "scenarios_container_name" {
  description = "Name of the training scenarios storage container"
  value       = azurerm_storage_container.scenarios_container.name
}

output "analytics_container_name" {
  description = "Name of the analytics storage container"
  value       = azurerm_storage_container.analytics_container.name
}

# ==============================================================================
# AZURE ACTIVE DIRECTORY OUTPUTS
# ==============================================================================

output "azure_ad_application_id" {
  description = "Application ID for Azure AD authentication"
  value       = azuread_application.training_app.application_id
}

output "azure_ad_application_name" {
  description = "Display name of the Azure AD application"
  value       = azuread_application.training_app.display_name
}

output "azure_ad_service_principal_id" {
  description = "Service principal ID for the Azure AD application"
  value       = azuread_service_principal.training_app_sp.id
}

output "azure_ad_service_principal_object_id" {
  description = "Object ID of the service principal"
  value       = azuread_service_principal.training_app_sp.object_id
}

output "azure_ad_tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "azure_ad_client_secret" {
  description = "Client secret for Azure AD application"
  value       = azuread_application_password.training_app_secret.value
  sensitive   = true
}

# ==============================================================================
# UNITY DEVELOPMENT OUTPUTS
# ==============================================================================

output "unity_configuration" {
  description = "Unity project configuration for Azure services integration"
  value = {
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
  }
}

# ==============================================================================
# DEPLOYMENT SUMMARY OUTPUTS
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    remote_rendering = {
      account_name = azurerm_mixed_reality_remote_rendering_account.arr_account.name
      account_id   = azurerm_mixed_reality_remote_rendering_account.arr_account.account_id
      purpose      = "Cloud-based 3D rendering for high-fidelity industrial models"
    }
    spatial_anchors = {
      account_name = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.name
      account_id   = azurerm_mixed_reality_spatial_anchors_account.spatial_anchors.account_id
      purpose      = "Spatial positioning and persistence for mixed reality content"
    }
    storage = {
      account_name = azurerm_storage_account.training_storage.name
      containers = {
        models    = azurerm_storage_container.models_container.name
        training  = azurerm_storage_container.training_container.name
        scenarios = azurerm_storage_container.scenarios_container.name
        analytics = azurerm_storage_container.analytics_container.name
      }
      purpose = "Centralized storage for 3D models, training content, and analytics"
    }
    azure_ad = {
      application_id = azuread_application.training_app.application_id
      application_name = azuread_application.training_app.display_name
      purpose = "Authentication and authorization for the training platform"
    }
  }
}

# ==============================================================================
# NEXT STEPS OUTPUTS
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the industrial training platform setup"
  value = [
    "1. Install Unity 2022.3 LTS with Mixed Reality Toolkit (MRTK) 3.0",
    "2. Configure Visual Studio 2022 with Universal Windows Platform development tools",
    "3. Import the Unity configuration from the storage account",
    "4. Set up HoloLens 2 device with Windows Mixed Reality",
    "5. Implement Azure Remote Rendering integration in Unity",
    "6. Configure spatial anchoring for equipment positioning",
    "7. Upload actual 3D industrial models to the models container",
    "8. Test the training scenarios on HoloLens 2 devices",
    "9. Implement user progress tracking and analytics",
    "10. Deploy to production environment with appropriate security measures"
  ]
}

# ==============================================================================
# IMPORTANT WARNINGS OUTPUT
# ==============================================================================

output "important_warnings" {
  description = "Important warnings and considerations for the deployment"
  value = [
    "⚠️  Azure Remote Rendering will be retired on September 30, 2025",
    "⚠️  Plan migration to alternative solutions before the retirement date",
    "⚠️  Remote Rendering sessions incur charges while active - monitor usage",
    "⚠️  Client secrets have a 90-day expiration - set up rotation process",
    "⚠️  Storage account contains sensitive training content - ensure proper access controls",
    "⚠️  Test all functionality in a development environment before production deployment"
  ]
}

# ==============================================================================
# COST ESTIMATION OUTPUTS
# ==============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the industrial training platform"
  value = {
    storage_account = "~$10-50/month depending on storage and transactions"
    remote_rendering = "~$1-5/hour per active session"
    spatial_anchors = "~$0.10-1/month per device"
    azure_ad = "Free for basic authentication"
    estimated_total = "$100-500/month for moderate usage with 10 concurrent users"
    cost_optimization_tips = [
      "Monitor Remote Rendering session usage to avoid unnecessary charges",
      "Use storage lifecycle policies to move old content to cooler tiers",
      "Implement session timeout to prevent idle rendering sessions",
      "Consider using Azure Reserved Instances for predictable workloads"
    ]
  }
}