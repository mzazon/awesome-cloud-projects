# main.tf - Main Terraform configuration for Azure cost optimization infrastructure
# This file contains the core infrastructure resources for proactive cost optimization

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current Azure subscription
data "azurerm_subscription" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and tagging
locals {
  # Generate consistent resource names with random suffix
  resource_names = {
    resource_group        = "${var.resource_group_name}-${random_id.suffix.hex}"
    storage_account      = "stcostopt${random_id.suffix.hex}"
    log_analytics        = "law-cost-optimization-${random_id.suffix.hex}"
    logic_app_plan      = "asp-cost-optimization-${random_id.suffix.hex}"
    logic_app           = "la-cost-optimization-${random_id.suffix.hex}"
    action_group        = "ag-cost-optimization-${random_id.suffix.hex}"
    budget_name         = "budget-optimization-${random_id.suffix.hex}"
    service_principal   = "sp-cost-optimization-${random_id.suffix.hex}"
  }
  
  # Merge common tags with environment-specific tags
  tags = merge(var.common_tags, {
    "Environment" = var.environment
    "Project"     = var.project_name
    "Location"    = var.location
  })
}

# Create the main resource group for cost optimization resources
resource "azurerm_resource_group" "cost_optimization" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.tags
}

# Create Log Analytics workspace for cost monitoring and analysis
resource "azurerm_log_analytics_workspace" "cost_optimization" {
  name                = local.resource_names.log_analytics
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  
  sku               = var.log_analytics_sku
  retention_in_days = var.log_analytics_retention_days
  
  tags = merge(local.tags, {
    "Service" = "Log Analytics"
    "Purpose" = "Cost Monitoring"
  })
}

# Create storage account for cost data exports and archival
resource "azurerm_storage_account" "cost_data" {
  name                = local.resource_names.storage_account
  resource_group_name = azurerm_resource_group.cost_optimization.name
  location            = azurerm_resource_group.cost_optimization.location
  
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind            = "StorageV2"
  access_tier             = "Hot"
  
  # Enable advanced security features
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  
  # Configure blob properties for cost data lifecycle management
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
    
    delete_retention_policy {
      days = var.cost_data_retention_days
    }
    
    versioning_enabled = true
  }
  
  tags = merge(local.tags, {
    "Service" = "Storage"
    "Purpose" = "Cost Data Export"
  })
}

# Create container for cost data exports
resource "azurerm_storage_container" "cost_exports" {
  name                  = "cost-exports"
  storage_account_name  = azurerm_storage_account.cost_data.name
  container_access_type = "private"
}

# Create container for cost analysis reports
resource "azurerm_storage_container" "cost_reports" {
  name                  = "cost-reports"
  storage_account_name  = azurerm_storage_account.cost_data.name
  container_access_type = "private"
}

# Create App Service Plan for Logic Apps Standard
resource "azurerm_service_plan" "logic_app_plan" {
  name                = local.resource_names.logic_app_plan
  resource_group_name = azurerm_resource_group.cost_optimization.name
  location            = azurerm_resource_group.cost_optimization.location
  
  os_type  = "Windows"
  sku_name = var.logic_app_plan_sku
  
  tags = merge(local.tags, {
    "Service" = "App Service Plan"
    "Purpose" = "Logic Apps Hosting"
  })
}

# Create Logic App for cost optimization automation
resource "azurerm_logic_app_standard" "cost_optimization" {
  name                = local.resource_names.logic_app
  resource_group_name = azurerm_resource_group.cost_optimization.name
  location            = azurerm_resource_group.cost_optimization.location
  
  app_service_plan_id = azurerm_service_plan.logic_app_plan.id
  
  storage_account_name       = azurerm_storage_account.cost_data.name
  storage_account_access_key = azurerm_storage_account.cost_data.primary_access_key
  
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "node"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "AZURE_SUBSCRIPTION_ID"        = data.azurerm_subscription.current.subscription_id
    "AZURE_TENANT_ID"              = data.azurerm_client_config.current.tenant_id
    "LOG_ANALYTICS_WORKSPACE_ID"   = azurerm_log_analytics_workspace.cost_optimization.workspace_id
    "TEAMS_WEBHOOK_URL"            = var.teams_webhook_url
    "BUDGET_AMOUNT"                = var.budget_amount
    "ANOMALY_THRESHOLD"            = var.anomaly_detection_threshold
  }
  
  tags = merge(local.tags, {
    "Service" = "Logic Apps"
    "Purpose" = "Cost Optimization Automation"
  })
}

# Create Azure AD application for cost management API access
resource "azuread_application" "cost_management" {
  display_name = local.resource_names.service_principal
  
  api {
    requested_access_token_version = 2
  }
  
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
  
  required_resource_access {
    resource_app_id = "https://management.azure.com/" # Azure Service Management
    
    resource_access {
      id   = "41094075-9dad-400e-a0bd-54e686782033" # user_impersonation
      type = "Scope"
    }
  }
}

# Create service principal for the Azure AD application
resource "azuread_service_principal" "cost_management" {
  application_id = azuread_application.cost_management.application_id
  use_existing   = true
}

# Create service principal password
resource "azuread_service_principal_password" "cost_management" {
  service_principal_id = azuread_service_principal.cost_management.object_id
  end_date            = timeadd(timestamp(), "8760h") # 1 year from now
}

# Assign Cost Management Reader role to service principal
resource "azurerm_role_assignment" "cost_management_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = azuread_service_principal.cost_management.object_id
}

# Assign Cost Management Contributor role to service principal (for budgets)
resource "azurerm_role_assignment" "cost_management_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Contributor"
  principal_id         = azuread_service_principal.cost_management.object_id
}

# Create Action Group for cost optimization notifications
resource "azurerm_monitor_action_group" "cost_optimization" {
  name                = local.resource_names.action_group
  resource_group_name = azurerm_resource_group.cost_optimization.name
  short_name          = "CostOpt"
  
  # Configure Logic App webhook action
  logic_app_receiver {
    name                    = "Cost Optimization Workflow"
    resource_id             = azurerm_logic_app_standard.cost_optimization.id
    callback_url            = "https://${azurerm_logic_app_standard.cost_optimization.default_hostname}/api/cost-optimization/triggers/manual/invoke"
    use_common_alert_schema = true
  }
  
  # Configure email notifications if provided
  dynamic "email_receiver" {
    for_each = var.email_notification_addresses
    content {
      name                    = "Cost Alert Email ${email_receiver.key + 1}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
  
  tags = merge(local.tags, {
    "Service" = "Monitor"
    "Purpose" = "Cost Optimization Alerts"
  })
}

# Create consumption budget for cost monitoring
resource "azurerm_consumption_budget_subscription" "cost_optimization" {
  name            = local.resource_names.budget_name
  subscription_id = data.azurerm_subscription.current.subscription_id
  
  amount     = var.budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h"))
  }
  
  # Create notifications for each threshold
  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThan"
      threshold_type = "Actual"
      
      contact_emails = var.email_notification_addresses
      
      contact_groups = [
        azurerm_monitor_action_group.cost_optimization.id
      ]
    }
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [
        azurerm_resource_group.cost_optimization.name
      ]
    }
  }
}

# Create cost anomaly detection alert rule if enabled
resource "azurerm_monitor_metric_alert" "cost_anomaly" {
  count = var.enable_anomaly_detection ? 1 : 0
  
  name                = "cost-anomaly-alert-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.cost_optimization.name
  scopes              = [data.azurerm_subscription.current.id]
  
  description = "Alert when cost exceeds ${var.anomaly_detection_threshold}% of monthly budget"
  severity    = 2
  frequency   = "PT1H"
  window_size = "PT1H"
  
  criteria {
    metric_namespace = "Microsoft.Consumption/budgets"
    metric_name      = "ActualCost"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.budget_amount * (var.anomaly_detection_threshold / 100)
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_optimization.id
  }
  
  tags = merge(local.tags, {
    "Service" = "Monitor"
    "Purpose" = "Cost Anomaly Detection"
  })
}

# Create storage lifecycle management policy for cost data
resource "azurerm_storage_management_policy" "cost_data_lifecycle" {
  storage_account_id = azurerm_storage_account.cost_data.id
  
  rule {
    name    = "cost-data-lifecycle"
    enabled = true
    
    filters {
      prefix_match = ["cost-exports/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = var.cost_data_retention_days
      }
      
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
      
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# Create diagnostic settings for cost optimization monitoring
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name               = "logic-app-diagnostics"
  target_resource_id = azurerm_logic_app_standard.cost_optimization.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.cost_optimization.id
  
  enabled_log {
    category = "WorkflowRuntime"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  metric {
    category = "AllMetrics"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Create diagnostic settings for storage account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name               = "storage-account-diagnostics"
  target_resource_id = azurerm_storage_account.cost_data.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.cost_optimization.id
  
  enabled_log {
    category = "StorageRead"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  enabled_log {
    category = "StorageWrite"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
  
  metric {
    category = "Transaction"
    
    retention_policy {
      enabled = true
      days    = var.log_analytics_retention_days
    }
  }
}

# Create Key Vault for storing sensitive configuration
resource "azurerm_key_vault" "cost_optimization" {
  name                = "kv-cost-opt-${random_id.suffix.hex}"
  location            = azurerm_resource_group.cost_optimization.location
  resource_group_name = azurerm_resource_group.cost_optimization.name
  
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Create", "Delete", "Get", "List", "Update", "Purge", "Recover"
    ]
    
    secret_permissions = [
      "Delete", "Get", "List", "Set", "Purge", "Recover"
    ]
  }
  
  # Access policy for service principal
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azuread_service_principal.cost_management.object_id
    
    secret_permissions = [
      "Get", "List"
    ]
  }
  
  tags = merge(local.tags, {
    "Service" = "Key Vault"
    "Purpose" = "Secrets Management"
  })
}

# Store service principal credentials in Key Vault
resource "azurerm_key_vault_secret" "service_principal_id" {
  name         = "service-principal-id"
  value        = azuread_application.cost_management.application_id
  key_vault_id = azurerm_key_vault.cost_optimization.id
  
  tags = merge(local.tags, {
    "Purpose" = "Service Principal Authentication"
  })
}

resource "azurerm_key_vault_secret" "service_principal_password" {
  name         = "service-principal-password"
  value        = azuread_service_principal_password.cost_management.value
  key_vault_id = azurerm_key_vault.cost_optimization.id
  
  tags = merge(local.tags, {
    "Purpose" = "Service Principal Authentication"
  })
}

# Store Teams webhook URL in Key Vault if provided
resource "azurerm_key_vault_secret" "teams_webhook_url" {
  count = var.teams_webhook_url != "" ? 1 : 0
  
  name         = "teams-webhook-url"
  value        = var.teams_webhook_url
  key_vault_id = azurerm_key_vault.cost_optimization.id
  
  tags = merge(local.tags, {
    "Purpose" = "Teams Integration"
  })
}