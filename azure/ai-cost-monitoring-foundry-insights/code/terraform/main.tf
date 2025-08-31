# Azure AI Cost Monitoring with Foundry and Application Insights
# This Terraform configuration deploys a comprehensive AI cost monitoring solution
# integrating Azure AI Foundry with Application Insights for real-time cost tracking

# ==============================================================================
# DATA SOURCES AND LOCALS
# ==============================================================================

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Define local values for consistent resource naming and tagging
locals {
  # Generate unique suffix for resource names
  suffix = lower(random_id.suffix.hex)
  
  # Default resource names with unique suffix
  resource_group_name          = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.suffix}"
  ai_hub_name                 = var.ai_hub_name != null ? var.ai_hub_name : "aihub-${var.project_name}-${local.suffix}"
  ai_project_name             = var.ai_project_name != null ? var.ai_project_name : "aiproject-${var.project_name}-${local.suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "logs-${var.project_name}-${local.suffix}"
  application_insights_name    = var.application_insights_name != null ? var.application_insights_name : "appins-${var.project_name}-${local.suffix}"
  storage_account_name        = var.storage_account_name != null ? var.storage_account_name : "stor${replace(var.project_name, "-", "")}${local.suffix}"
  action_group_name           = var.action_group_name != null ? var.action_group_name : "ag-${var.project_name}-${local.suffix}"
  
  # Standard tags applied to all resources
  default_tags = var.enable_default_tags ? {
    Environment      = var.environment
    Project         = var.project_name
    Purpose         = "ai-cost-monitoring"
    DeployedBy      = "terraform"
    CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
    ManagedBy       = "terraform"
  } : {}
  
  # Merge default tags with user-provided tags
  tags = merge(local.default_tags, var.tags)
  
  # Budget time period configuration
  budget_start_date = formatdate("YYYY-MM-01", timestamp())
  budget_end_date   = formatdate("YYYY-01-01", timeadd(timestamp(), "8760h")) # Next year
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Create the main resource group for all AI monitoring resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

# ==============================================================================
# LOG ANALYTICS AND APPLICATION INSIGHTS
# ==============================================================================

# Create Log Analytics Workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "log-analytics"
  })
}

# Create Application Insights for AI telemetry collection and analysis
resource "azurerm_application_insights" "main" {
  name                = local.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  # Enable custom metrics with dimensions for AI-specific tracking
  internet_ingestion_enabled = true
  internet_query_enabled     = true
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "application-insights"
  })
}

# ==============================================================================
# STORAGE ACCOUNT
# ==============================================================================

# Create Storage Account for AI Foundry artifacts and data storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  
  # Enable secure transfer and blob public access controls
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Configure blob properties for AI Foundry compatibility
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(local.tags, {
    Component = "storage"
    Service   = "ai-foundry"
  })
}

# ==============================================================================
# KEY VAULT FOR SECRETS MANAGEMENT
# ==============================================================================

# Create Key Vault for secure storage of AI service keys and connection strings
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  # Enable Key Vault for deployment and template deployment
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enabled_for_disk_encryption     = true
  
  # Configure network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = merge(local.tags, {
    Component = "security"
    Service   = "key-vault"
  })
}

# Grant current user access to Key Vault
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore"
  ]
}

# Store Application Insights connection string in Key Vault
resource "azurerm_key_vault_secret" "app_insights_connection_string" {
  name         = "app-insights-connection-string"
  value        = azurerm_application_insights.main.connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "application-insights"
  })
}

# ==============================================================================
# AZURE AI FOUNDRY (MACHINE LEARNING WORKSPACE)
# ==============================================================================

# Create AI Foundry Hub (Machine Learning Workspace with hub configuration)
resource "azurerm_machine_learning_workspace" "hub" {
  name                    = local.ai_hub_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  description             = var.ai_hub_description
  friendly_name           = "AI Foundry Hub - ${var.project_name}"
  
  # Link to Application Insights for monitoring
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  
  # Configure workspace identity
  identity {
    type = "SystemAssigned"
  }
  
  # Enable public network access for demo purposes
  public_network_access_enabled = true
  
  tags = merge(local.tags, {
    Component = "ai-foundry"
    Service   = "machine-learning"
    Type      = "hub"
  })
}

# Create AI Foundry Project (Machine Learning Workspace with project configuration)
resource "azurerm_machine_learning_workspace" "project" {
  name                    = local.ai_project_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  description             = var.ai_project_description
  friendly_name           = "AI Project - ${var.project_name}"
  
  # Link to the same infrastructure as the hub
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id           = azurerm_key_vault.main.id
  storage_account_id     = azurerm_storage_account.main.id
  
  # Configure workspace identity
  identity {
    type = "SystemAssigned"
  }
  
  # Enable public network access for demo purposes
  public_network_access_enabled = true
  
  tags = merge(local.tags, {
    Component = "ai-foundry"
    Service   = "machine-learning"
    Type      = "project"
    ParentHub = azurerm_machine_learning_workspace.hub.name
  })
}

# ==============================================================================
# ACTION GROUP FOR COST ALERTS
# ==============================================================================

# Create Action Group for automated cost alert notifications
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.main.name
  short_name          = var.action_group_short_name
  
  # Configure email notifications for budget alerts
  dynamic "email_receiver" {
    for_each = var.budget_notification_emails
    content {
      name          = "email-${replace(email_receiver.value, "@", "-at-")}"
      email_address = email_receiver.value
    }
  }
  
  # Configure webhook notification if URL is provided
  dynamic "webhook_receiver" {
    for_each = var.webhook_url != null ? [1] : []
    content {
      name        = "cost-webhook"
      service_uri = var.webhook_url
    }
  }
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "action-group"
  })
}

# ==============================================================================
# BUDGET AND COST MANAGEMENT
# ==============================================================================

# Create consumption budget for AI resources with automated alerting
resource "azurerm_consumption_budget_resource_group" "ai_budget" {
  name              = "budget-${var.project_name}-${local.suffix}"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.budget_amount
  time_grain        = "Monthly"
  
  time_period {
    start_date = local.budget_start_date
    end_date   = local.budget_end_date
  }
  
  # Configure budget filters to include all resources in the resource group
  filter {
    dimension {
      name = "ResourceGroup"
      values = [azurerm_resource_group.main.name]
    }
  }
  
  # Create notifications for each threshold percentage
  dynamic "notification" {
    for_each = { for idx, threshold in var.budget_alert_thresholds : "${threshold}percent" => threshold }
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThan"
      threshold_type = "Actual"
      
      contact_emails = var.budget_notification_emails
      contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
    }
  }
}

# ==============================================================================
# METRIC ALERTS FOR AI USAGE MONITORING
# ==============================================================================

# Create metric alert for high Application Insights request rate (proxy for AI usage)
resource "azurerm_monitor_metric_alert" "high_request_rate" {
  name                = "high-ai-request-rate-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when AI request rate exceeds normal thresholds"
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/rate"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 100
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "metric-alert"
    Type      = "request-rate"
  })
}

# Create metric alert for high Application Insights exception rate
resource "azurerm_monitor_metric_alert" "high_exception_rate" {
  name                = "high-ai-exception-rate-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when AI application exception rate is elevated"
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "exceptions/rate"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.cost_alerts.id
  }
  
  tags = merge(local.tags, {
    Component = "monitoring" 
    Service   = "metric-alert"
    Type      = "exception-rate"
  })
}

# ==============================================================================
# AZURE MONITOR WORKBOOK FOR COST VISUALIZATION
# ==============================================================================

# Create Azure Monitor Workbook for AI cost and usage visualization
resource "azurerm_application_insights_workbook" "ai_cost_dashboard" {
  name                = "ai-cost-dashboard-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = var.workbook_display_name
  description         = var.workbook_description
  
  # Workbook JSON template with AI cost monitoring queries
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# AI Cost Monitoring Dashboard\\n\\nComprehensive view of AI token usage, costs, and performance metrics across Azure AI Foundry and Application Insights."
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "customEvents\\n| where name == \"tokenUsage\" or name contains \"ai\"\\n| summarize \\n    TotalRequests = count(),\\n    AvgTokens = avg(todouble(customMeasurements.totalTokens)),\\n    EstimatedCost = sum(todouble(customMeasurements.estimatedCost))\\n    by bin(timestamp, 1h)\\n| render timechart"
          size = 0
          title = "AI Token Usage and Cost Over Time"
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "customEvents\\n| where name == \"tokenUsage\"\\n| summarize \\n    TotalCost = sum(todouble(customMeasurements.estimatedCost)),\\n    RequestCount = count()\\n    by tostring(customDimensions.modelName)\\n| order by TotalCost desc"
          size = 0
          title = "Cost by AI Model"
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "table"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "requests\\n| summarize \\n    RequestCount = count(),\\n    AvgDuration = avg(duration),\\n    SuccessRate = countif(success == true) * 100.0 / count()\\n    by bin(timestamp, 1h)\\n| render timechart"
          size = 0
          title = "AI Application Performance Metrics"
          queryType = 0
          resourceType = "microsoft.insights/components"
          visualization = "timechart"
        }
      }
    ]
  })
  
  tags = merge(local.tags, {
    Component = "monitoring"
    Service   = "workbook"
  })
}

# ==============================================================================
# RBAC ASSIGNMENTS
# ==============================================================================

# Grant AI Foundry Hub system-assigned identity access to Storage Account
resource "azurerm_role_assignment" "hub_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

# Grant AI Foundry Project system-assigned identity access to Storage Account
resource "azurerm_role_assignment" "project_storage_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.project.identity[0].principal_id
}

# Grant AI Foundry Hub system-assigned identity access to Application Insights
resource "azurerm_role_assignment" "hub_appinsights_access" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

# Grant AI Foundry Project system-assigned identity access to Application Insights  
resource "azurerm_role_assignment" "project_appinsights_access" {
  scope                = azurerm_application_insights.main.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_machine_learning_workspace.project.identity[0].principal_id
}