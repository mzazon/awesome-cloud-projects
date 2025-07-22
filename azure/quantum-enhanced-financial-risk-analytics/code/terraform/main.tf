# Azure Quantum-Enhanced Financial Risk Analytics Infrastructure
# This Terraform configuration deploys a comprehensive quantum-enhanced financial analytics platform
# combining Azure Quantum, Synapse Analytics, Machine Learning, and supporting services

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  suffix = random_string.suffix.result
  
  # Resource naming convention
  resource_names = {
    resource_group      = var.resource_group_name
    synapse_workspace   = "synapse-${var.project_name}-${local.suffix}"
    quantum_workspace   = "quantum-${var.project_name}-${local.suffix}"
    ml_workspace        = "ml-${var.project_name}-${local.suffix}"
    key_vault           = "kv-${var.project_name}-${local.suffix}"
    storage_account     = "st${var.project_name}${local.suffix}"
    data_lake           = "dls${var.project_name}${local.suffix}"
    app_insights        = "ai-${var.project_name}-${local.suffix}"
    log_analytics       = "la-${var.project_name}-${local.suffix}"
  }
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment        = var.environment
    Project           = var.project_name
    ManagedBy         = "Terraform"
    DeployedDate      = timestamp()
    QuantumEnabled    = "true"
    FinancialAnalytics = "true"
  })
}

# Primary resource group for all quantum finance analytics resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for comprehensive monitoring and logging
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.resource_names.log_analytics
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.common_tags
}

# Application Insights for application performance monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = local.resource_names.app_insights
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Azure Key Vault for secure credential and secret management
resource "azurerm_key_vault" "main" {
  name                = local.resource_names.key_vault
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Enable Key Vault for deployment and template deployment
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enabled_for_disk_encryption     = true
  
  # Soft delete and purge protection for production environments
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.environment == "prod" ? true : false
  
  # Network access rules for enhanced security
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    
    # Allow specified IP ranges
    ip_rules = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Key Vault access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge", "Recover"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge", "Recover"
  ]
}

# Generate secure password for Synapse SQL Administrator
resource "random_password" "synapse_sql_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Store Synapse SQL password in Key Vault
resource "azurerm_key_vault_secret" "synapse_sql_password" {
  name         = "synapse-sql-admin-password"
  value        = var.sql_administrator_password != null ? var.sql_administrator_password : random_password.synapse_sql_password.result
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# Data Lake Storage Gen2 for scalable financial data storage
resource "azurerm_storage_account" "data_lake" {
  name                     = local.resource_names.data_lake
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  
  # Enable hierarchical namespace for Data Lake Gen2
  is_hns_enabled = true
  
  # Enhanced security features
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Blob properties for optimal performance
  blob_properties {
    change_feed_enabled = true
    versioning_enabled  = true
    
    delete_retention_policy {
      days = 7
    }
    
    container_delete_retention_policy {
      days = 7
    }
  }
  
  # Network rules for secure access
  network_rules {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = local.common_tags
}

# Storage containers for organized financial data
resource "azurerm_storage_container" "market_data" {
  name                  = "market-data"
  storage_account_name  = azurerm_storage_account.data_lake.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "portfolio_data" {
  name                  = "portfolio-data"
  storage_account_name  = azurerm_storage_account.data_lake.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "risk_models" {
  name                  = "risk-models"
  storage_account_name  = azurerm_storage_account.data_lake.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "quantum_results" {
  name                  = "quantum-results"
  storage_account_name  = azurerm_storage_account.data_lake.name
  container_access_type = "private"
}

# Store Data Lake connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "data-lake-connection-string"
  value        = azurerm_storage_account.data_lake.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# Azure Synapse Analytics Workspace for unified analytics platform
resource "azurerm_synapse_workspace" "main" {
  name                                 = local.resource_names.synapse_workspace
  resource_group_name                  = azurerm_resource_group.main.name
  location                             = azurerm_resource_group.main.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  
  # SQL Administrator configuration
  sql_administrator_login          = var.sql_administrator_login
  sql_administrator_login_password = azurerm_key_vault_secret.synapse_sql_password.value
  
  # Azure AD authentication for enhanced security
  aad_admin {
    login     = data.azuread_client_config.current.display_name
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
  
  # Identity configuration for accessing other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  # Enable public network access (configure based on security requirements)
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = local.common_tags
  
  depends_on = [azurerm_storage_data_lake_gen2_filesystem.synapse]
}

# Data Lake Gen2 filesystem for Synapse workspace
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapsefilesystem"
  storage_account_id = azurerm_storage_account.data_lake.id
}

# Synapse firewall rule for development access
resource "azurerm_synapse_firewall_rule" "allow_azure_services" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# Additional firewall rules for specified IP ranges
resource "azurerm_synapse_firewall_rule" "allowed_ips" {
  count                = length(var.allowed_ip_ranges) > 1 ? length(var.allowed_ip_ranges) - 1 : 0
  name                 = "AllowedIP-${count.index}"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  start_ip_address     = split("/", var.allowed_ip_ranges[count.index + 1])[0]
  end_ip_address       = split("/", var.allowed_ip_ranges[count.index + 1])[0]
}

# Apache Spark pool for quantum algorithm integration and big data processing
resource "azurerm_synapse_spark_pool" "main" {
  name                 = "sparkpool01"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  node_size_family     = "MemoryOptimized"
  node_size            = var.spark_pool_node_size
  
  # Auto-scaling configuration for cost optimization
  auto_scale {
    max_node_count = var.spark_pool_max_nodes
    min_node_count = var.spark_pool_min_nodes
  }
  
  # Auto-pause to reduce costs during idle periods
  auto_pause {
    delay_in_minutes = 15
  }
  
  # Spark version optimized for financial analytics workloads
  spark_version = "3.3"
  
  # Library requirements for quantum computing integration
  library_requirement {
    content  = <<-EOT
      azure-quantum==1.0.1
      numpy>=1.21.0
      pandas>=1.3.0
      scipy>=1.7.0
      scikit-learn>=1.0.0
      matplotlib>=3.4.0
      seaborn>=0.11.0
      plotly>=5.0.0
      EOT
    filename = "requirements.txt"
  }
  
  tags = local.common_tags
}

# Azure Quantum Workspace for quantum computing capabilities
resource "azurerm_quantum_workspace" "main" {
  name                = local.resource_names.quantum_workspace
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  storage_account     = azurerm_storage_account.data_lake.id
  
  tags = local.common_tags
}

# Azure Machine Learning Workspace for advanced analytics and ML models
resource "azurerm_machine_learning_workspace" "main" {
  name                    = local.resource_names.ml_workspace
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = var.enable_monitoring ? azurerm_application_insights.main[0].id : null
  key_vault_id            = azurerm_key_vault.main.id
  storage_account_id      = azurerm_storage_account.data_lake.id
  
  # Identity configuration for accessing Azure services
  identity {
    type = "SystemAssigned"
  }
  
  # Enhanced security configuration
  public_network_access_enabled = !var.enable_private_endpoints
  
  tags = local.common_tags
}

# Machine Learning compute cluster for model training and inference
resource "azurerm_machine_learning_compute_cluster" "main" {
  name                          = "ml-cluster"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  vm_priority                   = "Dedicated"
  vm_size                       = "Standard_DS3_v2"
  
  # Auto-scaling configuration
  scale_settings {
    min_node_count                       = var.ml_compute_min_instances
    max_node_count                       = var.ml_compute_max_instances
    scale_down_nodes_after_idle_duration = "PT2M" # 2 minutes
  }
  
  # Identity for accessing other Azure services
  identity {
    type = "SystemAssigned"
  }
  
  # SSH configuration for debugging (disable in production)
  ssh {
    admin_username = "azureuser"
    key_value      = var.environment == "prod" ? null : "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7S..."
  }
  
  tags = local.common_tags
}

# Role assignments for service integration and permissions

# Synapse workspace managed identity access to Data Lake
resource "azurerm_role_assignment" "synapse_data_lake_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Synapse workspace access to Key Vault
resource "azurerm_role_assignment" "synapse_key_vault_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Machine Learning workspace access to Data Lake
resource "azurerm_role_assignment" "ml_data_lake_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Machine Learning compute cluster access to Data Lake
resource "azurerm_role_assignment" "ml_compute_data_lake_reader" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_machine_learning_compute_cluster.main.identity[0].principal_id
}

# Cosmos DB for real-time analytics and results storage
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.project_name}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  # Multi-region configuration for high availability
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
  
  # Consistency level optimized for financial analytics
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }
  
  # Enhanced security features
  enable_automatic_failover = true
  is_virtual_network_filter_enabled = var.enable_private_endpoints
  
  # Backup configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }
  
  tags = local.common_tags
}

# Cosmos DB database for financial analytics
resource "azurerm_cosmosdb_sql_database" "financial_analytics" {
  name                = "financial-analytics"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  
  # Throughput configuration
  throughput = 400
}

# Cosmos DB containers for different data types
resource "azurerm_cosmosdb_sql_container" "risk_metrics" {
  name                  = "risk-metrics"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.financial_analytics.name
  partition_key_path    = "/portfolioId"
  partition_key_version = 1
  throughput            = 400
  
  # Indexing policy optimized for financial queries
  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "quantum_results" {
  name                  = "quantum-optimization-results"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.financial_analytics.name
  partition_key_path    = "/optimizationId"
  partition_key_version = 1
  throughput            = 400
  
  # TTL for automatic cleanup of old results
  default_ttl = 2592000 # 30 days
}

# Store Cosmos DB connection string in Key Vault
resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  name         = "cosmos-db-connection-string"
  value        = azurerm_cosmosdb_account.main.primary_sql_connection_string
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# Sample market data API key (replace with actual API key in production)
resource "azurerm_key_vault_secret" "market_data_api_key" {
  name         = "market-data-api-key"
  value        = "sample-api-key-for-market-data-${local.suffix}"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_key_vault_access_policy.current_user]
  tags       = local.common_tags
}

# Private endpoints for enhanced security (conditional)
resource "azurerm_private_endpoint" "synapse" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-synapse-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  
  private_service_connection {
    name                           = "psc-synapse-${local.suffix}"
    private_connection_resource_id = azurerm_synapse_workspace.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }
  
  tags = local.common_tags
}

# Virtual Network for private endpoints (conditional)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${var.project_name}-${local.suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = local.common_tags
}

resource "azurerm_subnet" "private_endpoints" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
  
  private_endpoint_network_policies_enabled = false
}