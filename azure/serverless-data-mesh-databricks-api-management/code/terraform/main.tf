# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  resource_suffix = var.environment != "prod" ? "${var.environment}-${random_string.suffix.result}" : random_string.suffix.result
  
  # Resource names with fallback to generated names
  resource_group_name                   = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${local.resource_suffix}"
  databricks_workspace_name             = var.databricks_workspace_name != null ? var.databricks_workspace_name : "databricks-${local.resource_suffix}"
  databricks_managed_resource_group_name = var.databricks_managed_resource_group_name != null ? var.databricks_managed_resource_group_name : "rg-databricks-managed-${local.resource_suffix}"
  api_management_name                   = var.api_management_name != null ? var.api_management_name : "apim-${var.project_name}-${local.resource_suffix}"
  key_vault_name                        = var.key_vault_name != null ? var.key_vault_name : "kv-${var.project_name}-${local.resource_suffix}"
  event_grid_topic_name                 = var.event_grid_topic_name != null ? var.event_grid_topic_name : "eg-${var.project_name}-${local.resource_suffix}"
  log_analytics_workspace_name          = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "log-${var.project_name}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    created_by = "terraform"
    created_at = timestamp()
  })
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Create Azure Databricks Workspace
resource "azurerm_databricks_workspace" "main" {
  name                          = local.databricks_workspace_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = var.databricks_sku
  managed_resource_group_name   = local.databricks_managed_resource_group_name
  public_network_access_enabled = !var.databricks_enable_no_public_ip
  network_security_group_rules_required = "NoAzureDatabricksRules"
  
  tags = local.common_tags

  custom_parameters {
    no_public_ip = var.databricks_enable_no_public_ip
  }
}

# Create Key Vault for secure credential management
resource "azurerm_key_vault" "main" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = var.key_vault_purge_protection_enabled
  sku_name                    = var.key_vault_sku
  enable_rbac_authorization   = var.key_vault_enable_rbac
  
  tags = local.common_tags

  # Network ACLs
  network_acls {
    bypass                     = "AzureServices"
    default_action             = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }
}

# Key Vault Access Policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  count        = var.key_vault_enable_rbac ? 0 : 1
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]

  certificate_permissions = [
    "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
  ]
}

# RBAC role assignment for Key Vault (if RBAC is enabled)
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  count                = var.key_vault_enable_rbac ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create Event Grid Topic for data product events
resource "azurerm_eventgrid_topic" "main" {
  name                = local.event_grid_topic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  input_schema        = var.event_grid_topic_input_schema
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

# Create API Management Service
resource "azurerm_api_management" "main" {
  name                = local.api_management_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name
  tags                = local.common_tags

  identity {
    type = var.enable_system_assigned_identity ? "SystemAssigned" : null
  }
}

# API Management Logger (for monitoring)
resource "azurerm_api_management_logger" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "apim-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  resource_id         = azurerm_log_analytics_workspace.main[0].id

  application_insights {
    instrumentation_key = azurerm_application_insights.main[0].instrumentation_key
  }
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.project_name}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Create Service Principal for Databricks
resource "azuread_application" "databricks" {
  display_name = "sp-databricks-${local.resource_suffix}"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "databricks" {
  application_id = azuread_application.databricks.application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal_password" "databricks" {
  service_principal_id = azuread_service_principal.databricks.object_id
  display_name         = "Databricks Service Principal Password"
}

# Role assignment for Databricks service principal
resource "azurerm_role_assignment" "databricks_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.databricks.object_id
}

# Store Databricks workspace URL in Key Vault
resource "azurerm_key_vault_secret" "databricks_url" {
  name         = "databricks-url"
  value        = "https://${azurerm_databricks_workspace.main.workspace_url}"
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.key_vault_secrets_officer
  ]
}

# Store Databricks service principal credentials in Key Vault
resource "azurerm_key_vault_secret" "databricks_sp_id" {
  name         = "databricks-sp-id"
  value        = azuread_service_principal.databricks.application_id
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "databricks_sp_secret" {
  name         = "databricks-sp-secret"
  value        = azuread_service_principal_password.databricks.value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.key_vault_secrets_officer
  ]
}

# Store Event Grid credentials in Key Vault
resource "azurerm_key_vault_secret" "eventgrid_endpoint" {
  name         = "eventgrid-endpoint"
  value        = azurerm_eventgrid_topic.main.endpoint
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.key_vault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "eventgrid_key" {
  name         = "eventgrid-key"
  value        = azurerm_eventgrid_topic.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.current_user,
    azurerm_role_assignment.key_vault_secrets_officer
  ]
}

# Create data product APIs in API Management
resource "azurerm_api_management_api" "data_products" {
  for_each = { for api in var.data_product_apis : api.name => api }

  name                  = each.value.name
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = each.value.display_name
  path                  = each.value.path
  protocols             = ["https"]
  description           = each.value.description
  version               = "1.0"
  version_set_id        = azurerm_api_management_api_version_set.data_products[each.key].id

  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.1"
      info = {
        title       = each.value.display_name
        description = each.value.description
        version     = "1.0"
      }
      servers = [
        {
          url = "https://${azurerm_api_management.main.name}.azure-api.net/${each.value.path}"
        }
      ]
      paths = {
        "/metrics" = {
          get = {
            summary     = "Get ${each.value.display_name} metrics"
            operationId = "get${replace(title(each.value.display_name), " ", "")}Metrics"
            parameters = [
              {
                name     = "dateFrom"
                in       = "query"
                required = true
                schema = {
                  type   = "string"
                  format = "date"
                }
              }
            ]
            responses = {
              "200" = {
                description = "Successful response"
                content = {
                  "application/json" = {
                    schema = {
                      type = "object"
                      properties = {
                        data = {
                          type = "array"
                          items = {
                            type = "object"
                          }
                        }
                        metadata = {
                          type = "object"
                          properties = {
                            count = {
                              type = "integer"
                            }
                            lastUpdated = {
                              type   = "string"
                              format = "date-time"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })
  }
}

# Create API Version Sets for data products
resource "azurerm_api_management_api_version_set" "data_products" {
  for_each = { for api in var.data_product_apis : api.name => api }

  name                = "${each.value.name}-version-set"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "${each.value.display_name} Version Set"
  versioning_scheme   = "Query"
  version_query_name  = "version"
}

# Create API subscriptions for data products
resource "azurerm_api_management_subscription" "data_consumers" {
  for_each = { for api in var.data_product_apis : api.name => api }

  subscription_id     = "${each.value.name}-subscription"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "${each.value.display_name} Subscription"
  scope               = azurerm_api_management_api.data_products[each.key].id
  state               = "active"
}

# Create API policies for governance
resource "azurerm_api_management_api_policy" "data_products" {
  for_each = { for api in var.data_product_apis : api.name => api }

  api_name            = azurerm_api_management_api.data_products[each.key].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/.well-known/openid-configuration" />
      <audiences>
        <audience>https://${azurerm_api_management.main.name}.azure-api.net</audience>
      </audiences>
    </validate-jwt>
    <rate-limit calls="100" renewal-period="60" />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <cache-store duration="300" />
    <set-header name="X-Data-Product" exists-action="override">
      <value>${each.value.name}</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Create Event Grid subscription for data product updates
resource "azurerm_eventgrid_event_subscription" "data_product_updates" {
  name  = "data-product-updates"
  scope = azurerm_eventgrid_topic.main.id

  webhook_endpoint {
    url = "https://webhook.site/unique-endpoint-${random_string.suffix.result}"
  }

  included_event_types = [
    "DataProductUpdated",
    "DataProductCreated"
  ]

  retry_policy {
    event_time_to_live    = 1440
    max_delivery_attempts = 30
  }

  depends_on = [azurerm_eventgrid_topic.main]
}

# Grant API Management access to Key Vault
resource "azurerm_role_assignment" "apim_key_vault_secrets_user" {
  count                = var.enable_system_assigned_identity ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
}

# Create diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "databricks" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "databricks-diagnostics"
  target_resource_id = azurerm_databricks_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "dbfs"
  }

  enabled_log {
    category = "clusters"
  }

  enabled_log {
    category = "accounts"
  }

  enabled_log {
    category = "jobs"
  }

  enabled_log {
    category = "notebook"
  }

  enabled_log {
    category = "ssh"
  }

  enabled_log {
    category = "workspace"
  }
}

resource "azurerm_monitor_diagnostic_setting" "api_management" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "apim-diagnostics"
  target_resource_id = azurerm_api_management.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "GatewayLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "event_grid" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "eventgrid-diagnostics"
  target_resource_id = azurerm_eventgrid_topic.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_log {
    category = "PublishFailures"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Wait for API Management to be fully provisioned
resource "time_sleep" "wait_for_apim" {
  depends_on = [azurerm_api_management.main]
  create_duration = "30s"
}