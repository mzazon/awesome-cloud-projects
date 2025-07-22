# Azure Quantum-Enhanced Machine Learning Infrastructure
# This Terraform configuration deploys a complete hybrid quantum-classical ML pipeline
# integrating Azure Quantum, Azure Machine Learning, Azure Batch, and supporting services

# Data sources for current client configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_string.suffix.result
  
  # Conditional resource names based on variables or defaults with suffix
  quantum_workspace_name   = var.quantum_workspace_name != "" ? var.quantum_workspace_name : "${var.resource_prefix}-quantum-ws-${local.resource_suffix}"
  ml_workspace_name       = var.ml_workspace_name != "" ? var.ml_workspace_name : "${var.resource_prefix}-aml-ws-${local.resource_suffix}"
  storage_account_name    = var.storage_account_name != "" ? var.storage_account_name : "${replace(var.resource_prefix, "-", "")}st${local.resource_suffix}"
  batch_account_name      = var.batch_account_name != "" ? var.batch_account_name : "${replace(var.resource_prefix, "-", "")}batch${local.resource_suffix}"
  key_vault_name         = var.key_vault_name != "" ? var.key_vault_name : "${var.resource_prefix}-kv-${local.resource_suffix}"
  
  # Derived resource names
  resource_group_name           = "${var.resource_prefix}-rg-${local.resource_suffix}"
  container_registry_name       = "${replace(var.resource_prefix, "-", "")}acr${local.resource_suffix}"
  application_insights_name     = "${var.resource_prefix}-ai-${local.resource_suffix}"
  log_analytics_workspace_name  = "${var.resource_prefix}-law-${local.resource_suffix}"
  virtual_network_name         = "${var.resource_prefix}-vnet-${local.resource_suffix}"
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Environment   = var.environment
    DeployedBy    = "terraform"
    CreatedDate   = timestamp()
    ResourceGroup = local.resource_group_name
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Storage Account with Data Lake Gen2 capabilities
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable Data Lake Storage Gen2
  is_hns_enabled = var.enable_data_lake
  
  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for versioning and soft delete
  blob_properties {
    versioning_enabled       = true
    last_access_time_enabled = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network rules for enhanced security
  network_rules {
    default_action             = "Allow"
    ip_rules                   = var.allowed_ip_ranges
    bypass                     = ["AzureServices"]
  }
  
  tags = local.common_tags
}

# Storage containers for ML data and quantum results
resource "azurerm_storage_container" "quantum_ml_data" {
  name                  = "quantum-ml-data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "quantum_results" {
  name                  = "quantum-results"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "ml_models" {
  name                  = "ml-models"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secure credential and secret management
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = false
  
  # Access policies
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete", "Recover",
      "Backup", "Restore", "GetRotationPolicy", "SetRotationPolicy"
    ]
    
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
    ]
    
    certificate_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete", "Recover",
      "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers",
      "ListIssuers", "SetIssuers", "DeleteIssuers"
    ]
  }
  
  # Network ACLs
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count = var.enable_application_insights ? 1 : 0
  
  name                = local.application_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = var.application_insights_type
  
  tags = local.common_tags
}

# Azure Container Registry for custom ML environments
resource "azurerm_container_registry" "main" {
  count = var.enable_container_registry ? 1 : 0
  
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = false
  
  # Network rule set for enhanced security
  dynamic "network_rule_set" {
    for_each = var.container_registry_sku == "Premium" ? [1] : []
    content {
      default_action = "Allow"
      
      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }
  
  tags = local.common_tags
}

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "main" {
  name                    = local.ml_workspace_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  storage_account_id      = azurerm_storage_account.main.id
  key_vault_id           = azurerm_key_vault.main.id
  application_insights_id = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
  container_registry_id   = var.enable_container_registry ? azurerm_container_registry.main[0].id : null
  
  # Identity configuration for secure access
  identity {
    type = "SystemAssigned"
  }
  
  # Public network access configuration
  public_network_access_enabled = true
  
  # High business impact for enhanced security
  high_business_impact = false
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_application_insights.main,
    azurerm_container_registry.main
  ]
}

# Azure Machine Learning Compute Instance for development
resource "azurerm_machine_learning_compute_instance" "quantum_ml_compute" {
  name                          = "quantum-ml-compute"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  virtual_machine_size          = var.ml_compute_instance_size
  
  # Assign to current user
  assign_to_user {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
  }
  
  # Auto-shutdown schedule for cost optimization
  dynamic "schedules" {
    for_each = var.enable_auto_shutdown ? [1] : []
    content {
      compute_start_stop {
        start_time = null
        stop_time  = var.auto_shutdown_time
        time_zone  = "UTC"
        trigger    = "Recurrence"
        
        recurrence {
          frequency = "Week"
          interval  = 1
          week_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        }
      }
    }
  }
  
  tags = local.common_tags
}

# Azure Machine Learning Compute Cluster for training
resource "azurerm_machine_learning_compute_cluster" "quantum_ml_cluster" {
  name                          = "quantum-ml-cluster"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  vm_priority                   = "Dedicated"
  vm_size                       = var.ml_compute_instance_size
  
  # Scale settings
  scale_settings {
    min_node_count                       = var.ml_compute_cluster_min_nodes
    max_node_count                       = var.ml_compute_cluster_max_nodes
    scale_down_nodes_after_idle_duration = "PT30M" # 30 minutes
  }
  
  # Identity for secure access to resources
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Azure Batch Account for quantum job orchestration
resource "azurerm_batch_account" "main" {
  name                                = local.batch_account_name
  resource_group_name                 = azurerm_resource_group.main.name
  location                            = azurerm_resource_group.main.location
  pool_allocation_mode                = var.batch_pool_allocation_mode
  storage_account_id                  = azurerm_storage_account.main.id
  storage_account_authentication_mode = "StorageKeys"
  
  # Public network access configuration
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Azure Quantum Workspace
resource "azurerm_quantum_workspace" "main" {
  name                = local.quantum_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  storage_account     = azurerm_storage_account.main.id
  
  # Identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Virtual Network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                = local.virtual_network_name
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

# Private subnet for private endpoints
resource "azurerm_subnet" "private" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.private_subnet_address_prefix]
  
  # Enable private endpoint network policies
  private_endpoint_network_policies_enabled = false
}

# Public subnet for other resources
resource "azurerm_subnet" "public" {
  count = var.enable_private_endpoints ? 1 : 0
  
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.public_subnet_address_prefix]
}

# Role assignments for ML workspace identity
resource "azurerm_role_assignment" "ml_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "ml_key_vault_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Role assignments for Quantum workspace identity
resource "azurerm_role_assignment" "quantum_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_quantum_workspace.main.identity[0].principal_id
}

# Store Batch account key in Key Vault
resource "azurerm_key_vault_secret" "batch_account_key" {
  name         = "batch-account-key"
  value        = azurerm_batch_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_key_vault.main]
}

# Store storage account connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_key_vault.main]
}

# Diagnostic settings for monitoring
resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  name                       = "ml-workspace-diagnostics"
  target_resource_id         = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = [
      "AmlComputeClusterEvent",
      "AmlComputeClusterNodeEvent",
      "AmlComputeJobEvent",
      "AmlComputeCpuGpuUtilization",
      "AmlRunStatusChangedEvent"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "key-vault-diagnostics"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  dynamic "enabled_log" {
    for_each = [
      "AuditEvent",
      "AzurePolicyEvaluationDetails"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = "storage-account-diagnostics"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  metric {
    category = "Capacity"
    enabled  = true
  }
  
  metric {
    category = "Transaction"
    enabled  = true
  }
}

# Time delay to ensure proper resource initialization
resource "time_sleep" "wait_for_workspace" {
  depends_on = [
    azurerm_machine_learning_workspace.main,
    azurerm_quantum_workspace.main
  ]
  
  create_duration = "30s"
}