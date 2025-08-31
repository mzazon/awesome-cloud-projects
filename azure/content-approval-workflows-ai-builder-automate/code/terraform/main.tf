# Content Approval Workflows with AI Builder and Power Automate
# This Terraform configuration creates the infrastructure foundation for
# intelligent content approval workflows using Microsoft 365 and Power Platform services

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# Data source to get current Azure AD tenant information
data "azuread_client_config" "current" {}

# Data source to get current Azure subscription
data "azurerm_client_config" "current" {}

# Create Resource Group for all content approval resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = merge(var.tags, {
    Purpose = "Content Approval Workflows"
    Service = "SharePoint, Power Automate, AI Builder, Teams"
  })
}

# Log Analytics Workspace for monitoring and analytics
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.monitoring_settings.enable_log_analytics ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.monitoring_settings.log_retention_days
  tags                = var.tags
}

# Application Insights for Power Platform workflow monitoring
resource "azurerm_application_insights" "main" {
  count               = var.monitoring_settings.enable_application_insights ? 1 : 0
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = var.monitoring_settings.enable_log_analytics ? azurerm_log_analytics_workspace.main[0].id : null
  application_type    = "web"
  tags                = var.tags
}

# Azure AD Application for Power Platform integration
resource "azuread_application" "power_platform" {
  display_name     = "ContentApproval-PowerPlatform-${random_string.suffix.result}"
  description      = "Application for Power Platform content approval workflows"
  sign_in_audience = "AzureADMyOrg"
  
  # Required resource access for Microsoft Graph and SharePoint
  required_resource_access {
    # Microsoft Graph
    resource_app_id = "00000003-0000-0000-c000-000000000000"
    
    resource_access {
      # Read and write all users' profiles
      id   = "b4e74841-8e56-480b-be8b-910348b18b4c"
      type = "Scope"
    }
    
    resource_access {
      # Read and write all groups
      id   = "62a82d76-70ea-41e2-9197-370581804d09"
      type = "Scope"
    }
    
    resource_access {
      # Read and write files in all site collections
      id   = "89fe6a52-be36-487e-b7d8-d061c450a026"
      type = "Scope"
    }
  }
  
  required_resource_access {
    # SharePoint Online
    resource_app_id = "00000003-0000-0ff1-ce00-000000000000"
    
    resource_access {
      # Read and write items and lists in all site collections
      id   = "640ddd16-e5b7-4d71-9690-3f4022699ee7"
      type = "Scope"
    }
  }
  
  # Web application configuration
  web {
    homepage_url  = "https://make.powerapps.com/"
    redirect_uris = [
      "https://global.consent.azure-apim.net/redirect",
      "https://make.powerapps.com/",
      "https://make.powerautomate.com/"
    ]
  }
  
  # API configuration for Power Platform
  api {
    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access content approval workflows"
      admin_consent_display_name = "Access content approval workflows"
      enabled                    = true
      id                         = random_string.suffix.result
      type                       = "User"
      user_consent_description   = "Allow the application to access content approval workflows on your behalf"
      user_consent_display_name  = "Access content approval workflows"
      value                      = "access_workflows"
    }
  }
}

# Service Principal for the Azure AD Application
resource "azuread_service_principal" "power_platform" {
  application_id               = azuread_application.power_platform.application_id
  app_role_assignment_required = false
  description                  = "Service principal for Power Platform content approval integration"
  
  tags = [
    "PowerPlatform",
    "ContentApproval",
    "AIBuilder",
    "PowerAutomate"
  ]
}

# Key Vault for storing sensitive configuration and secrets
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable soft delete and purge protection for production environments
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = var.tags
}

# Key Vault access policy for the current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore"
  ]
  
  key_permissions = [
    "Get",
    "List",
    "Create",
    "Update",
    "Delete",
    "Recover",
    "Backup",
    "Restore"
  ]
}

# Key Vault access policy for Power Platform service principal
resource "azurerm_key_vault_access_policy" "power_platform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azuread_service_principal.power_platform.object_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Store Power Platform application configuration in Key Vault
resource "azurerm_key_vault_secret" "power_platform_app_id" {
  name         = "PowerPlatformApplicationId"
  value        = azuread_application.power_platform.application_id
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = var.tags
}

resource "azurerm_key_vault_secret" "power_platform_tenant_id" {
  name         = "PowerPlatformTenantId"
  value        = data.azuread_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = var.tags
}

# Storage Account for workflow data and temporary file processing
resource "azurerm_storage_account" "workflow_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "GRS" : "LRS"
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true
  
  # Enable blob encryption
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    
    delete_retention_policy {
      days = var.security_settings.retention_period_days
    }
    
    container_delete_retention_policy {
      days = var.security_settings.retention_period_days
    }
  }
  
  tags = var.tags
}

# Storage container for document processing
resource "azurerm_storage_container" "document_processing" {
  name                  = "document-processing"
  storage_account_name  = azurerm_storage_account.workflow_storage.name
  container_access_type = "private"
}

# Storage container for workflow logs
resource "azurerm_storage_container" "workflow_logs" {
  name                  = "workflow-logs"
  storage_account_name  = azurerm_storage_account.workflow_storage.name
  container_access_type = "private"
}

# Azure Function App for custom workflow logic (optional)
resource "azurerm_service_plan" "workflow_functions" {
  name                = "asp-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.environment == "prod" ? "S1" : "Y1"
  
  tags = var.tags
}

resource "azurerm_linux_function_app" "workflow_functions" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  service_plan_id            = azurerm_service_plan.workflow_functions.id
  storage_account_name       = azurerm_storage_account.workflow_storage.name
  storage_account_access_key = azurerm_storage_account.workflow_storage.primary_access_key
  
  # Enable Application Insights integration
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME         = "python"
    FUNCTIONS_EXTENSION_VERSION      = "~4"
    APPINSIGHTS_INSTRUMENTATIONKEY   = var.monitoring_settings.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : ""
    KEY_VAULT_URL                    = azurerm_key_vault.main.vault_uri
    POWER_PLATFORM_APP_ID            = azuread_application.power_platform.application_id
    TENANT_ID                        = data.azuread_client_config.current.tenant_id
    SHAREPOINT_SITE_NAME             = var.sharepoint_site_name
    DOCUMENT_LIBRARY_NAME            = var.document_library_name
  }
  
  site_config {
    application_stack {
      python_version = "3.9"
    }
    
    # CORS settings for Power Platform integration
    cors {
      allowed_origins = [
        "https://make.powerapps.com",
        "https://make.powerautomate.com",
        "https://*.sharepoint.com",
        "https://teams.microsoft.com"
      ]
      support_credentials = true
    }
  }
  
  # Managed identity for secure access to other Azure resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = var.tags
}

# Grant Function App access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.workflow_functions.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Action Group for alerting and notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.monitoring_settings.enable_alerts ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ContentApp"
  
  # Email notification (if email provided)
  dynamic "email_receiver" {
    for_each = var.monitoring_settings.alert_email != "" ? [1] : []
    content {
      name          = "AdminEmail"
      email_address = var.monitoring_settings.alert_email
    }
  }
  
  tags = var.tags
}

# Metric alerts for Function App monitoring
resource "azurerm_monitor_metric_alert" "function_errors" {
  count               = var.monitoring_settings.enable_alerts ? 1 : 0
  name                = "alert-func-errors-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.workflow_functions.id]
  description         = "Alert when function app has high error rate"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}

# Budget alert for cost monitoring
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_id = azurerm_resource_group.main.id
  
  amount     = var.environment == "prod" ? 500 : 100
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h")) # 1 year from now
  }
  
  notification {
    enabled   = true
    threshold = 80
    operator  = "EqualTo"
    
    contact_emails = var.monitoring_settings.alert_email != "" ? [var.monitoring_settings.alert_email] : []
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "EqualTo"
    
    contact_emails = var.monitoring_settings.alert_email != "" ? [var.monitoring_settings.alert_email] : []
  }
}

# Local file to store Power Platform configuration
resource "local_file" "power_platform_config" {
  filename = "${path.module}/power-platform-config.json"
  content = jsonencode({
    tenantId                    = data.azuread_client_config.current.tenant_id
    applicationId               = azuread_application.power_platform.application_id
    sharepointSiteName          = var.sharepoint_site_name
    documentLibraryName         = var.document_library_name
    keyVaultUrl                 = azurerm_key_vault.main.vault_uri
    functionAppUrl              = "https://${azurerm_linux_function_app.workflow_functions.default_hostname}"
    storageAccountName          = azurerm_storage_account.workflow_storage.name
    resourceGroupName           = azurerm_resource_group.main.name
    environment                 = var.environment
    approvalWorkflowSettings    = var.approval_workflow_settings
    teamsIntegration           = var.teams_integration
    securitySettings           = var.security_settings
    powerPlatformSettings      = var.power_platform_settings
    monitoringSettings         = var.monitoring_settings
  })
  
  depends_on = [
    azurerm_key_vault.main,
    azurerm_linux_function_app.workflow_functions,
    azuread_application.power_platform
  ]
}