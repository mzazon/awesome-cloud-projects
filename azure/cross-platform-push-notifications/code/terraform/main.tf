# Data sources for current client configuration
data "azurerm_client_config" "current" {}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = var.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  tags                = var.tags
}

# Key Vault for secure credential storage
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name != "" ? var.key_vault_name : "kv-push${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  # Enable RBAC for modern access control
  enable_rbac_authorization = true

  # Network access rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  # Soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags
}

# Notification Hub Namespace
resource "azurerm_notification_hub_namespace" "main" {
  name                = var.notification_hub_namespace_name != "" ? var.notification_hub_namespace_name : "nhns-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  namespace_type      = "NotificationHub"
  sku_name            = var.notification_hub_sku
  tags                = var.tags
}

# Notification Hub
resource "azurerm_notification_hub" "main" {
  name                = var.notification_hub_name
  namespace_name      = azurerm_notification_hub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# Azure Spring Apps Service
resource "azurerm_spring_cloud_service" "main" {
  name                = var.spring_apps_name != "" ? var.spring_apps_name : "asa-pushnotif-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.spring_apps_sku

  # Enable Application Insights integration
  trace {
    connection_string = azurerm_application_insights.main.connection_string
  }

  tags = var.tags
}

# Spring Cloud Application
resource "azurerm_spring_cloud_app" "notification_api" {
  name                = var.spring_app_name
  resource_group_name = azurerm_resource_group.main.name
  service_name        = azurerm_spring_cloud_service.main.name

  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Enable persistent storage if needed
  persistent_disk {
    size_in_gb = 50
  }

  # Enable HTTPS only
  https_only = true
}

# Role assignment for Spring App to access Key Vault
resource "azurerm_role_assignment" "spring_app_key_vault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_spring_cloud_app.notification_api.identity[0].principal_id

  depends_on = [
    azurerm_spring_cloud_app.notification_api,
    azurerm_key_vault.main
  ]
}

# Store platform credentials in Key Vault
resource "azurerm_key_vault_secret" "fcm_server_key" {
  name         = "fcm-server-key"
  value        = var.fcm_server_key
  key_vault_id = azurerm_key_vault.main.id
  content_type = "FCM Server Key for Android push notifications"
  tags         = var.tags

  depends_on = [
    azurerm_key_vault.main
  ]
}

resource "azurerm_key_vault_secret" "apns_key_id" {
  name         = "apns-key-id"
  value        = var.apns_key_id
  key_vault_id = azurerm_key_vault.main.id
  content_type = "APNS Key ID for iOS push notifications"
  tags         = var.tags

  depends_on = [
    azurerm_key_vault.main
  ]
}

resource "azurerm_key_vault_secret" "vapid_public_key" {
  name         = "vapid-public-key"
  value        = var.vapid_public_key
  key_vault_id = azurerm_key_vault.main.id
  content_type = "VAPID Public Key for web push notifications"
  tags         = var.tags

  depends_on = [
    azurerm_key_vault.main
  ]
}

resource "azurerm_key_vault_secret" "vapid_private_key" {
  name         = "vapid-private-key"
  value        = var.vapid_private_key
  key_vault_id = azurerm_key_vault.main.id
  content_type = "VAPID Private Key for web push notifications"
  tags         = var.tags

  depends_on = [
    azurerm_key_vault.main
  ]
}

# Store Notification Hub connection string in Key Vault
resource "azurerm_key_vault_secret" "notification_hub_connection" {
  name         = "notification-hub-connection"
  value        = azurerm_notification_hub_namespace.main.default_access_policy[0].primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  content_type = "Azure Notification Hub connection string"
  tags         = var.tags

  depends_on = [
    azurerm_key_vault.main,
    azurerm_notification_hub_namespace.main
  ]
}

# Spring Cloud App deployment with environment variables
resource "azurerm_spring_cloud_app_deployment" "notification_api" {
  name                = "default"
  spring_cloud_app_id = azurerm_spring_cloud_app.notification_api.id
  instance_count      = 1
  cpu                 = 1
  memory_in_gb        = 2
  runtime_version     = "Java_11"

  # Environment variables for the Spring Boot application
  environment_variables = {
    "AZURE_KEYVAULT_URI"                     = azurerm_key_vault.main.vault_uri
    "NOTIFICATION_HUB_NAMESPACE"             = azurerm_notification_hub_namespace.main.name
    "NOTIFICATION_HUB_NAME"                  = azurerm_notification_hub.main.name
    "APPLICATIONINSIGHTS_CONNECTION_STRING"  = azurerm_application_insights.main.connection_string
    "SPRING_PROFILES_ACTIVE"                 = var.environment
  }

  # JVM options for performance tuning
  jvm_options = "-Xms1024m -Xmx1536m -XX:+UseG1GC -XX:+UseStringDeduplication"

  depends_on = [
    azurerm_spring_cloud_app.notification_api,
    azurerm_key_vault.main,
    azurerm_notification_hub.main,
    azurerm_application_insights.main,
    azurerm_role_assignment.spring_app_key_vault
  ]
}

# Diagnostic settings for Notification Hub
resource "azurerm_monitor_diagnostic_setting" "notification_hub" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "notification-hub-diagnostics"
  target_resource_id         = azurerm_notification_hub_namespace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable all available metrics
  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Spring Cloud Service
resource "azurerm_monitor_diagnostic_setting" "spring_cloud" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "spring-cloud-diagnostics"
  target_resource_id         = azurerm_spring_cloud_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Enable application logs
  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Metric alerts for notification failures
resource "azurerm_monitor_metric_alert" "notification_failures" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "notification-failures-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_notification_hub_namespace.main.id]
  description         = "Alert when notification failure rate exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.NotificationHubs/namespaces"
    metric_name      = "outgoing.allpns.invalidpayload"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.notification_alerts[0].id
  }

  tags = var.tags
}

# Action group for notifications
resource "azurerm_monitor_action_group" "notification_alerts" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "notification-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "notif-alert"

  # Add email notification (customize as needed)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
  }

  tags = var.tags
}

# Network Security Group for Spring Cloud (if needed for advanced networking)
resource "azurerm_network_security_group" "spring_cloud" {
  count               = var.environment == "prod" ? 1 : 0
  name                = "nsg-spring-cloud"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Dashboard for monitoring (optional)
resource "azurerm_dashboard" "notification_dashboard" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "Push-Notification-Dashboard"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x = 0
              y = 0
              colSpan = 6
              rowSpan = 4
            }
            metadata = {
              inputs = [{
                name = "resourceId"
                value = azurerm_notification_hub_namespace.main.id
              }]
              type = "Extension/Microsoft_Azure_NotificationHubs/PartType/NotificationHubMetrics"
            }
          }
          "1" = {
            position = {
              x = 6
              y = 0
              colSpan = 6
              rowSpan = 4
            }
            metadata = {
              inputs = [{
                name = "resourceId"
                value = azurerm_spring_cloud_service.main.id
              }]
              type = "Extension/Microsoft_Azure_Spring/PartType/SpringCloudMetrics"
            }
          }
        }
      }
    }
  })

  tags = var.tags
}