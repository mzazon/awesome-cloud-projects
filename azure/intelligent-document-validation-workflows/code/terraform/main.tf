# Main Terraform configuration for Azure document validation workflow
# This configuration deploys a complete enterprise-grade solution for automated
# document processing using Azure AI Document Intelligence, Logic Apps, and Dataverse

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Generate random password for SQL authentication (if needed)
resource "random_password" "sql_admin_password" {
  length  = 16
  special = true
}

# Local values for resource naming and tagging
locals {
  # Resource naming convention
  resource_suffix = random_string.suffix.result
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment         = var.environment
    Project            = var.project_name
    Purpose            = "document-validation"
    ManagedBy          = "terraform"
    LastUpdated        = timestamp()
    CostCenter         = "IT-Operations"
    DataClassification = "internal"
    Backup             = var.enable_backup ? "required" : "not-required"
  }, var.additional_tags)
  
  # Resource names with consistent naming convention
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${local.resource_prefix}-${local.resource_suffix}"
  storage_account_name = replace("st${var.project_name}${var.environment}${local.resource_suffix}", "-", "")
  key_vault_name = "kv-${local.resource_prefix}-${local.resource_suffix}"
  document_intelligence_name = "docint-${local.resource_prefix}-${local.resource_suffix}"
  logic_app_name = "logic-${local.resource_prefix}-${local.resource_suffix}"
  log_analytics_name = "law-${local.resource_prefix}-${local.resource_suffix}"
  app_insights_name = "ai-${local.resource_prefix}-${local.resource_suffix}"
  app_service_plan_name = "asp-${local.resource_prefix}-${local.resource_suffix}"
  
  # Network configuration for private endpoints
  subnet_names = {
    logic_apps = "snet-logicapps-${local.resource_suffix}"
    storage    = "snet-storage-${local.resource_suffix}"
    keyvault   = "snet-keyvault-${local.resource_suffix}"
    cognitive  = "snet-cognitive-${local.resource_suffix}"
  }
}

# Primary resource group for all document validation resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "vnet-${local.resource_prefix}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.virtual_network_address_space
  tags                = local.common_tags
}

# Subnets for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  for_each = var.enable_private_endpoints ? local.subnet_names : {}
  
  name                 = each.value
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [cidrsubnet(var.virtual_network_address_space[0], 8, index(keys(local.subnet_names), each.key))]
  
  private_endpoint_network_policies_enabled = false
}

# Log Analytics workspace for monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_in_days
  tags                = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_application_type
  tags                = local.common_tags
}

# Storage account for document processing and Logic Apps runtime
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = var.enable_private_endpoints ? false : true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  
  # Advanced security features
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = var.backup_retention_days
    }
    
    container_delete_retention_policy {
      days = var.backup_retention_days
    }
  }
  
  # Network access control
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.enable_private_endpoints ? [for subnet in azurerm_subnet.private_endpoints : subnet.id] : []
      bypass                     = ["AzureServices"]
    }
  }
  
  tags = local.common_tags
}

# Storage containers for document processing workflow
resource "azurerm_storage_container" "containers" {
  for_each = toset(var.storage_containers)
  
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secure credential and secret management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Security configuration
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # Network access control
  public_network_access_enabled = var.enable_private_endpoints ? false : true
  
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.enable_private_endpoints ? [for subnet in azurerm_subnet.private_endpoints : subnet.id] : []
    }
  }
  
  tags = local.common_tags
}

# Key Vault access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

# Azure AI Document Intelligence (Form Recognizer) service
resource "azurerm_cognitive_account" "document_intelligence" {
  name                = local.document_intelligence_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FormRecognizer"
  sku_name            = var.document_intelligence_sku
  
  # Custom subdomain for private endpoint support
  custom_subdomain_name = var.document_intelligence_custom_subdomain != null ? var.document_intelligence_custom_subdomain : "docint-${local.resource_suffix}"
  
  # Network access control
  public_network_access_enabled = var.enable_private_endpoints ? false : true
  
  dynamic "network_acls" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      ip_rules       = var.allowed_ip_ranges
      
      dynamic "virtual_network_rules" {
        for_each = var.enable_private_endpoints ? [azurerm_subnet.private_endpoints["cognitive"].id] : []
        content {
          subnet_id = virtual_network_rules.value
        }
      }
    }
  }
  
  tags = local.common_tags
}

# Store Document Intelligence credentials in Key Vault
resource "azurerm_key_vault_secret" "document_intelligence_endpoint" {
  name         = "DocumentIntelligenceEndpoint"
  value        = azurerm_cognitive_account.document_intelligence.endpoint
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

resource "azurerm_key_vault_secret" "document_intelligence_key" {
  name         = "DocumentIntelligenceKey"
  value        = azurerm_cognitive_account.document_intelligence.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "StorageConnectionString"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# App Service Plan for Logic Apps Standard
resource "azurerm_service_plan" "logic_apps" {
  name                = local.app_service_plan_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Windows"
  sku_name            = var.logic_app_plan_sku
  
  tags = local.common_tags
}

# Logic Apps Standard for document processing workflow
resource "azurerm_logic_app_standard" "main" {
  name                       = local.logic_app_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  app_service_plan_id        = azurerm_service_plan.logic_apps.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  
  # Application settings for Logic Apps
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                   = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"               = "~18"
    "AzureWebJobsFeatureFlags"                   = "EnableWorkerIndexing"
    "WEBSITE_CONTENTOVERVNET"                    = var.enable_private_endpoints ? "1" : "0"
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.main.connection_string
    
    # Custom settings for document processing
    "DocumentIntelligenceEndpoint"               = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DocumentIntelligenceEndpoint)"
    "DocumentIntelligenceKey"                    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=DocumentIntelligenceKey)"
    "StorageConnectionString"                    = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=StorageConnectionString)"
    
    # Validation rules configuration
    "ApprovalThresholdAmount"                    = var.document_validation_rules.approval_threshold_amount
    "RequiredConfidenceScore"                    = var.document_validation_rules.required_confidence_score
    "AutoApproveUnderAmount"                     = var.document_validation_rules.auto_approve_under_amount
    
    # Performance settings
    "WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT"  = var.max_concurrent_requests
    "AzureFunctionsJobHost__functionTimeout"     = "00:05:00"
  }
  
  # Security configuration
  site_config {
    always_on                              = var.logic_app_always_on
    ftps_state                            = "Disabled"
    http2_enabled                         = true
    minimum_tls_version                   = "1.2"
    scm_minimum_tls_version              = "1.2"
    use_32_bit_worker                    = false
    
    # IP restrictions for security
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        ip_address  = ip_restriction.value
        action      = "Allow"
        priority    = 100 + ip_restriction.key
        name        = "AllowedIP-${ip_restriction.key}"
      }
    }
  }
  
  # Managed identity for secure access to other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Key Vault access policy for Logic Apps managed identity
resource "azurerm_key_vault_access_policy" "logic_apps" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_logic_app_standard.main.identity[0].tenant_id
  object_id    = azurerm_logic_app_standard.main.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# Role assignment for Logic Apps to access Cognitive Services
resource "azurerm_role_assignment" "logic_apps_cognitive" {
  scope                = azurerm_cognitive_account.document_intelligence.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# Role assignment for Logic Apps to access Storage Account
resource "azurerm_role_assignment" "logic_apps_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_standard.main.identity[0].principal_id
}

# Diagnostic settings for monitoring (if enabled)
resource "azurerm_monitor_diagnostic_setting" "document_intelligence" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "diag-${azurerm_cognitive_account.document_intelligence.name}"
  target_resource_id         = azurerm_cognitive_account.document_intelligence.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Audit"
  }
  
  enabled_log {
    category = "RequestResponse"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "logic_apps" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "diag-${azurerm_logic_app_standard.main.name}"
  target_resource_id         = azurerm_logic_app_standard.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count = var.enable_diagnostic_settings ? 1 : 0
  
  name                       = "diag-${azurerm_storage_account.main.name}"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "Transaction"
  }
  
  metric {
    category = "Capacity"
  }
}

# Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.resource_prefix}-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "docval"
  
  # Email notification (customize as needed)
  email_receiver {
    name                    = "admin"
    email_address          = "admin@company.com"
    use_common_alert_schema = true
  }
  
  tags = local.common_tags
}

# Alert rule for Document Intelligence failures
resource "azurerm_monitor_metric_alert" "document_intelligence_failures" {
  name                = "Document Processing Failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cognitive_account.document_intelligence.id]
  description         = "Alert when document processing fails repeatedly"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "ClientErrors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# Alert rule for Logic Apps failures
resource "azurerm_monitor_metric_alert" "logic_apps_failures" {
  name                = "Logic Apps Workflow Failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_logic_app_standard.main.id]
  description         = "Alert when Logic Apps workflows fail repeatedly"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "LessThan"
    threshold        = 1
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  
  tags = local.common_tags
}

# Private endpoints (if enabled)
resource "azurerm_private_endpoint" "storage" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-${azurerm_storage_account.main.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints["storage"].id
  
  private_service_connection {
    name                           = "psc-${azurerm_storage_account.main.name}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names             = ["blob"]
    is_manual_connection          = false
  }
  
  tags = local.common_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-${azurerm_key_vault.main.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints["keyvault"].id
  
  private_service_connection {
    name                           = "psc-${azurerm_key_vault.main.name}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names             = ["vault"]
    is_manual_connection          = false
  }
  
  tags = local.common_tags
}

resource "azurerm_private_endpoint" "cognitive" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = "pe-${azurerm_cognitive_account.document_intelligence.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints["cognitive"].id
  
  private_service_connection {
    name                           = "psc-${azurerm_cognitive_account.document_intelligence.name}"
    private_connection_resource_id = azurerm_cognitive_account.document_intelligence.id
    subresource_names             = ["account"]
    is_manual_connection          = false
  }
  
  tags = local.common_tags
}

# Time delay to ensure all resources are properly configured
resource "time_sleep" "wait_for_deployment" {
  depends_on = [
    azurerm_logic_app_standard.main,
    azurerm_cognitive_account.document_intelligence,
    azurerm_key_vault_access_policy.logic_apps,
    azurerm_role_assignment.logic_apps_cognitive,
    azurerm_role_assignment.logic_apps_storage
  ]
  
  create_duration = "60s"
}