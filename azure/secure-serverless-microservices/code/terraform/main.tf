# ========================================
# Data Sources
# ========================================

# Get current client configuration (user/service principal)
data "azurerm_client_config" "current" {}

# Get current Azure AD user for Key Vault access policies
data "azuread_user" "current" {
  object_id = data.azurerm_client_config.current.object_id
}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ========================================
# Core Infrastructure
# ========================================

# Resource Group - Container for all resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace - Centralized logging for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Application Insights - Application Performance Monitoring
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_days
  tags                = var.tags
}

# ========================================
# Container Registry
# ========================================

# Azure Container Registry - Private Docker registry
resource "azurerm_container_registry" "main" {
  name                = "acr${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.container_registry_admin_enabled
  
  # Enable public network access (can be disabled for enhanced security)
  public_network_access_enabled = var.container_registry_public_network_access
  
  # Enable network rule set for IP restrictions
  network_rule_set {
    default_action = "Allow"
    
    # IP rules for restricted access (optional)
    dynamic "ip_rule" {
      for_each = var.container_registry_public_network_access ? [] : var.allowed_ip_ranges
      content {
        action   = "Allow"
        ip_range = ip_rule.value
      }
    }
  }
  
  tags = var.tags
}

# ========================================
# Key Vault
# ========================================

# Azure Key Vault - Centralized secret management
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id           = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled = var.key_vault_purge_protection_enabled
  sku_name            = var.key_vault_sku
  
  # Network access configuration
  public_network_access_enabled = var.key_vault_public_network_access == "Enabled"
  
  # Network ACLs for restricted access
  network_acls {
    bypass                     = "AzureServices"
    default_action             = var.key_vault_public_network_access == "Enabled" ? "Allow" : "Deny"
    ip_rules                   = var.key_vault_public_network_access == "Enabled" ? [] : var.allowed_ip_ranges
    virtual_network_subnet_ids = []
  }
  
  tags = var.tags
}

# Key Vault Access Policy - Current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge",
    "Backup",
    "Restore",
    "Recover"
  ]
  
  key_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Purge",
    "Backup",
    "Restore",
    "Recover"
  ]
  
  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Purge",
    "Backup",
    "Restore",
    "Recover"
  ]
}

# Sample secrets for demonstration
resource "azurerm_key_vault_secret" "database_connection" {
  name         = "DatabaseConnectionString"
  value        = "${var.database_connection_string}-${random_string.suffix.result}"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "ApiKey"
  value        = "${var.api_key}-${random_string.suffix.result}"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "service_bus_connection" {
  name         = "ServiceBusConnection"
  value        = var.service_bus_connection
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]
  tags         = var.tags
}

# ========================================
# Container Apps Environment
# ========================================

# Container Apps Environment - Managed Kubernetes environment
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  # Infrastructure configuration
  infrastructure_subnet_id                     = null
  internal_load_balancer_enabled              = var.container_apps_environment_internal_load_balancer
  zone_redundancy_enabled                     = var.container_apps_environment_zone_redundant
  
  tags = var.tags
}

# ========================================
# Container Apps
# ========================================

# API Service Container App - Public-facing API service
resource "azurerm_container_app" "api_service" {
  name                         = var.api_service_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Container configuration
  template {
    min_replicas = var.api_service_min_replicas
    max_replicas = var.api_service_max_replicas
    
    container {
      name   = "api-service"
      image  = var.api_service_image
      cpu    = var.api_service_cpu
      memory = var.api_service_memory
      
      # Environment variables with Key Vault secret references
      env {
        name        = "DATABASE_CONNECTION"
        secret_name = "db-connection"
      }
      
      env {
        name        = "API_KEY"
        secret_name = "api-key"
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
  }
  
  # Ingress configuration for external access
  ingress {
    allow_insecure_connections = false
    external_enabled          = true
    target_port               = var.api_service_target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  
  # Secret configuration with Key Vault references
  secret {
    name                = "db-connection"
    identity            = azurerm_user_assigned_identity.api_service.id
    key_vault_secret_id = azurerm_key_vault_secret.database_connection.id
  }
  
  secret {
    name                = "api-key"
    identity            = azurerm_user_assigned_identity.api_service.id
    key_vault_secret_id = azurerm_key_vault_secret.api_key.id
  }
  
  # Container Registry authentication
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.api_service.id
  }
  
  # Managed identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api_service.id]
  }
  
  tags = var.tags
}

# Worker Service Container App - Internal background service
resource "azurerm_container_app" "worker_service" {
  name                         = var.worker_service_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Container configuration
  template {
    min_replicas = var.worker_service_min_replicas
    max_replicas = var.worker_service_max_replicas
    
    container {
      name   = "worker-service"
      image  = var.worker_service_image
      cpu    = var.worker_service_cpu
      memory = var.worker_service_memory
      
      # Environment variables with Key Vault secret references
      env {
        name        = "SERVICE_BUS_CONNECTION"
        secret_name = "service-bus-connection"
      }
      
      env {
        name        = "API_KEY"
        secret_name = "api-key"
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
    }
  }
  
  # Ingress configuration for internal access only
  ingress {
    allow_insecure_connections = false
    external_enabled          = false
    target_port               = var.worker_service_target_port
    
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  
  # Secret configuration with Key Vault references
  secret {
    name                = "service-bus-connection"
    identity            = azurerm_user_assigned_identity.worker_service.id
    key_vault_secret_id = azurerm_key_vault_secret.service_bus_connection.id
  }
  
  secret {
    name                = "api-key"
    identity            = azurerm_user_assigned_identity.worker_service.id
    key_vault_secret_id = azurerm_key_vault_secret.api_key.id
  }
  
  # Container Registry authentication
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.worker_service.id
  }
  
  # Managed identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.worker_service.id]
  }
  
  tags = var.tags
}

# ========================================
# Managed Identities
# ========================================

# User-assigned managed identity for API service
resource "azurerm_user_assigned_identity" "api_service" {
  location            = azurerm_resource_group.main.location
  name                = "id-${var.api_service_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# User-assigned managed identity for worker service
resource "azurerm_user_assigned_identity" "worker_service" {
  location            = azurerm_resource_group.main.location
  name                = "id-${var.worker_service_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# ========================================
# Key Vault Access Policies for Container Apps
# ========================================

# Key Vault access policy for API service managed identity
resource "azurerm_key_vault_access_policy" "api_service" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.api_service.principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# Key Vault access policy for worker service managed identity
resource "azurerm_key_vault_access_policy" "worker_service" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.worker_service.principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
}

# ========================================
# RBAC Role Assignments
# ========================================

# Grant Container Registry pull permissions to API service identity
resource "azurerm_role_assignment" "api_service_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.api_service.principal_id
}

# Grant Container Registry pull permissions to worker service identity
resource "azurerm_role_assignment" "worker_service_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.worker_service.principal_id
}

# ========================================
# Monitoring and Alerts
# ========================================

# Action Group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ContainerApp"
  
  # Email notification (configure as needed)
  email_receiver {
    name          = "admin"
    email_address = "admin@example.com"
    use_common_alert_schema = true
  }
  
  tags = var.tags
}

# CPU usage alert for API service
resource "azurerm_monitor_metric_alert" "api_service_cpu" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "cpu-alert-${var.api_service_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.api_service.id]
  description         = "Alert when CPU usage exceeds ${var.cpu_alert_threshold}%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "CpuUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}

# Memory usage alert for API service
resource "azurerm_monitor_metric_alert" "api_service_memory" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "memory-alert-${var.api_service_name}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.api_service.id]
  description         = "Alert when memory usage exceeds ${var.memory_alert_threshold}%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "MemoryUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.memory_alert_threshold
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
  
  tags = var.tags
}