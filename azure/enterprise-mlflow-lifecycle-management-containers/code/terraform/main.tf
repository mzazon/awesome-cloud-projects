# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# LOCAL VALUES
# =============================================================================

locals {
  # Generate unique names if not provided
  resource_group_name   = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  ml_workspace_name     = var.ml_workspace_name != "" ? var.ml_workspace_name : "mlws-${var.project_name}-${random_string.suffix.result}"
  storage_account_name  = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  key_vault_name        = "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  container_registry_name = "acr${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  container_app_env_name = "cae-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  container_app_name    = "ca-model-serve-${var.environment}-${random_string.suffix.result}"
  log_analytics_name    = "law-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  app_insights_name     = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge({
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "Terraform"
    Purpose      = "MLflow-Lifecycle-Management"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  }, var.additional_tags)
}

# =============================================================================
# RESOURCE GROUP
# =============================================================================

# Main resource group for all MLflow lifecycle resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# STORAGE ACCOUNT
# =============================================================================

# Storage account for Azure ML workspace and model artifacts
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network access rules
  network_rules {
    default_action             = "Allow" # Consider restricting in production
    ip_rules                   = var.allowed_ip_ranges
    bypass                     = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# =============================================================================
# KEY VAULT
# =============================================================================

# Key Vault for storing secrets and certificates
resource "azurerm_key_vault" "main" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.key_vault_soft_delete_retention_days
  purge_protection_enabled    = false # Set to true for production
  sku_name                    = var.key_vault_sku
  
  # Network access rules
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow" # Consider restricting in production
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "ManageContacts", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers"
  ]
}

# =============================================================================
# CONTAINER REGISTRY
# =============================================================================

# Azure Container Registry for storing model serving images
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  
  # Network access rules
  network_rule_set {
    default_action = "Allow" # Consider restricting in production
    
    dynamic "ip_rule" {
      for_each = var.allowed_ip_ranges
      content {
        action   = "Allow"
        ip_range = ip_rule.value
      }
    }
  }
  
  tags = local.common_tags
}

# =============================================================================
# LOG ANALYTICS AND APPLICATION INSIGHTS
# =============================================================================

# Log Analytics workspace for monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  tags = local.common_tags
}

# =============================================================================
# AZURE MACHINE LEARNING WORKSPACE
# =============================================================================

# Azure Machine Learning workspace with MLflow integration
resource "azurerm_machine_learning_workspace" "main" {
  name                    = local.ml_workspace_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.main.id
  key_vault_id            = azurerm_key_vault.main.id
  storage_account_id      = azurerm_storage_account.main.id
  container_registry_id   = azurerm_container_registry.main.id
  
  # Enable system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  # Public network access configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}

# Key Vault access policy for ML workspace managed identity
resource "azurerm_key_vault_access_policy" "ml_workspace" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_machine_learning_workspace.main.identity[0].tenant_id
  object_id    = azurerm_machine_learning_workspace.main.identity[0].principal_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update"
  ]
}

# =============================================================================
# CONTAINER APPS ENVIRONMENT
# =============================================================================

# Container Apps environment for hosting model serving applications
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_app_env_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = local.common_tags
}

# =============================================================================
# CONTAINER APP FOR MODEL SERVING
# =============================================================================

# Container app for serving ML models
resource "azurerm_container_app" "model_serving" {
  name                         = local.container_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Container app template configuration
  template {
    min_replicas = var.container_app_min_replicas
    max_replicas = var.container_app_max_replicas
    
    # Container configuration
    container {
      name   = "model-serving"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest" # Placeholder image
      cpu    = var.container_app_cpu
      memory = var.container_app_memory
      
      # Environment variables for model serving
      env {
        name  = "MODEL_NAME"
        value = var.model_name
      }
      
      env {
        name  = "MODEL_VERSION"
        value = var.model_version
      }
      
      env {
        name  = "AZURE_ML_WORKSPACE_NAME"
        value = azurerm_machine_learning_workspace.main.name
      }
      
      env {
        name  = "AZURE_RESOURCE_GROUP"
        value = azurerm_resource_group.main.name
      }
      
      env {
        name  = "AZURE_SUBSCRIPTION_ID"
        value = data.azurerm_client_config.current.subscription_id
      }
      
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
    
    # HTTP scaling rule based on concurrent requests
    http_scale_rule {
      name                = "http-requests"
      concurrent_requests = "10"
    }
  }
  
  # Ingress configuration for external access
  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8080
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
  
  # Registry configuration for private container images
  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "registry-password"
  }
  
  # Secret for container registry password
  secret {
    name  = "registry-password"
    value = azurerm_container_registry.main.admin_password
  }
  
  tags = local.common_tags
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Action group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "mlflowag"
  
  dynamic "email_receiver" {
    for_each = var.alert_email_recipients
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
  
  tags = local.common_tags
}

# Alert rule for high response latency
resource "azurerm_monitor_metric_alert" "high_latency" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "High Response Latency - ${local.container_app_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.model_serving.id]
  description         = "Alert when model serving response time exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000 # 5 seconds
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Alert rule for unhealthy container app
resource "azurerm_monitor_metric_alert" "container_app_unhealthy" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "Container App Unhealthy - ${local.container_app_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.model_serving.id]
  description         = "Alert when container app replicas are unhealthy"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Replicas"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# Alert rule for low model accuracy (custom metric)
resource "azurerm_monitor_metric_alert" "low_model_accuracy" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "Low Model Accuracy - ${local.container_app_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Alert when model accuracy drops below threshold"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  
  criteria {
    metric_namespace = "Azure.ApplicationInsights"
    metric_name      = "customMetrics/modelAccuracy"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 0.8 # 80% accuracy threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = local.common_tags
}

# =============================================================================
# ROLE ASSIGNMENTS
# =============================================================================

# Role assignment for ML workspace to access storage account
resource "azurerm_role_assignment" "ml_workspace_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Role assignment for ML workspace to access container registry
resource "azurerm_role_assignment" "ml_workspace_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Role assignment for container app to access container registry
resource "azurerm_role_assignment" "container_app_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.model_serving.identity[0].principal_id
}

# =============================================================================
# OPTIONAL: PRIVATE ENDPOINTS
# =============================================================================

# Private endpoint for storage account (if enabled)
resource "azurerm_private_endpoint" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_storage_account.main.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "psc-storage"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

# Private endpoint for Key Vault (if enabled)
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${azurerm_key_vault.main.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

# Virtual network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Subnet for private endpoints (if enabled)
resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
  
  private_endpoint_network_policies_enabled = false
}